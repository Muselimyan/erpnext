# ==============================================================
# A7 - ONE DEFINITION OF DEBT
#
# Five consumers each computed "what this customer owes" differently. They
# disagreed on two independent axes -- gross vs net, and which ledger they read
# -- so a Director and a collector could look at the same customer and see
# different numbers, and two Director-facing threshold reports could contradict
# each other.
#
#   BEFORE                                                    basis
#   Scheduled-debt-collection (Debt Alert, hourly)     GL sum(debit-credit), by company
#   Scheduled-debt-collection-episodes (daily)         SUM(SI.outstanding)  <- GROSS
#   task_debt_panel                                    outstanding - ALL credit
#   RPT - Clients Exceeding Debt Threshold             outstanding - ALL credit
#   RPT - Risk - Debt Threshold Exceeded               GL sum(debit-credit), no company
#
#   AFTER, everywhere:
#     net = unpaid submitted invoices - UNTAGGED unallocated credit
#
# WHY ONLY UNTAGGED CREDIT. A Payment Entry carrying a dispatch_case is
# earmarked, and task_commit_invoice already refuses to spend it on another
# case. Subtracting it here contradicted a rule the system enforces elsewhere,
# and it under-reported risk: a client holding a large advance for next month
# appeared to owe nothing on this month's unpaid invoice.
#
# WHY INVOICE-BASED, NOT GL-BASED. docs/implementation-questions.md specifies
# outstanding from submitted Sales Invoices, and it is what the collector's own
# panel shows. The GL form swept in every customer-party movement regardless of
# origin.
#
# MEASURED ON TEST BEFORE THE CHANGE (a7-probe-debt-bases.py):
#   - 1 Company, so the company-filter divergence between the two GL consumers
#     was theoretical: identical for every customer.
#   - gross and net disagree for 3 of 6 customers with a position. One shows
#     gross 2,340,000 against a net of 0 -- the concrete case of a client being
#     chased for money already in hand.
#   - 0 customers change threshold verdict from the untagged-credit rule today,
#     so that half is PREVENTIVE rather than remedial. Stated plainly rather
#     than oversold.
#   - Payment Entry Reference rows ARE written when an advance is consumed
#     (5 of 5), so RPT - Receivables - Unallocated Advances already agrees with
#     PE.unallocated_amount and needs no change.
#
# ALSO HERE
#   - the episode description now surfaces available credit, because the overdue
#     trigger stays gross on purpose (an invoice 40 days late deserves
#     attention) and the right first action in that case is to APPLY the credit,
#     not to telephone.
#   - the debt panel splits credit into available vs earmarked, so Net
#     Receivable reconciles against the tiles beside it.
#   - RPT - Risk - Debt Threshold Exceeded is RETIRED as the duplicate of
#     RPT - Clients Exceeding Debt Threshold, and its workspace shortcut is
#     repointed. Two Director reports answering one question with two formulas
#     is worse than one.
#
# TEST ONLY. Credentials read from deploy/test/export.ps1.
#
#   ... -Mode Check
#   ... -Mode Deploy
#   ... -Mode Deploy -ConfirmDeletions   (also retires the duplicate report)
# ==============================================================

param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check",
    [switch]$ConfirmDeletions
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$TestRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$WorkDir = Join-Path $TestRoot "work"
$ConfigPath = Join-Path $TestRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

if ($BaseUrl -notmatch "test\.erpnext\.am") {
    throw "Refusing to run: resolved base URL '$BaseUrl' is not the test instance."
}

Write-Host "A7 one debt definition -> $BaseUrl  [Mode=$Mode  ConfirmDeletions=$($ConfirmDeletions.IsPresent)]" -ForegroundColor Cyan
Write-Host ""

function Enc([string]$s) { [uri]::EscapeDataString($s) }

function Invoke-Erp { param([string]$Method, [string]$Path, $Body = $null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 180 }
    $Json = $Body | ConvertTo-Json -Depth 40
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 180
}

function Get-ErpDoc { param([string]$DocType, [string]$Name)
    # Explicit UTF-8 decode -- Invoke-RestMethod decodes responses as Latin-1
    # when no charset is declared, producing false "DIFFERS" for non-ASCII.
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Encoding = [System.Text.Encoding]::UTF8
        $wc.Headers.Add("Authorization", "token $($ApiKey):$($ApiSec)")
        $text = $wc.DownloadString("$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)")
        return ($text | ConvertFrom-Json).data
    } catch { return $null }
}

function Read-WorkScript { param([string]$Path)
    # -Encoding UTF8 is REQUIRED: PowerShell 5.1 reads BOM-less files as ANSI.
    $raw = Get-Content $Path -Raw -Encoding UTF8
    $marker = if ($Path -like "*.js") { "// ---" } else { "# ---" }
    $i = $raw.IndexOf($marker)
    if ($i -lt 0) { return $raw }
    return $raw.Substring($i + $marker.Length).TrimStart("`r", "`n")
}

# ── 1. Server + client scripts ────────────────────────────────────────
$Scripts = @(
    @{ Name = "Scheduled-debt-collection"; File = "server\Scheduled-debt-collection.py"; Type = "Server Script"; Field = "script" },
    @{ Name = "Scheduled-debt-collection-episodes"; File = "server\Scheduled-debt-collection-episodes.py"; Type = "Server Script"; Field = "script" },
    @{ Name = "task_debt_panel"; File = "server\task_debt_panel.py"; Type = "Server Script"; Field = "script" },
    @{ Name = "Task-Debt-Panel"; File = "client\Task-Debt-Panel.js"; Type = "Client Script"; Field = "script" }
)

Write-Host "[1] Scripts" -ForegroundColor Magenta
foreach ($s in $Scripts) {
    $path = Join-Path $WorkDir $s.File
    if (-not (Test-Path $path)) { throw "Missing work file: $path" }
    $body = Read-WorkScript $path
    $existing = Get-ErpDoc $s.Type $s.Name
    if (-not $existing) {
        Write-Host ("  {0,-38} MISSING ON SERVER - not creating here" -f $s.Name) -ForegroundColor Red
        continue
    }
    $same = ($existing.($s.Field) -replace "`r`n", "`n").TrimEnd() -eq ($body -replace "`r`n", "`n").TrimEnd()
    if ($Mode -eq "Check") {
        Write-Host ("  {0,-38} {1}" -f $s.Name, $(if ($same) { "identical" } else { "DIFFERS (cur=$($existing.($s.Field).Length) new=$($body.Length))" })) -ForegroundColor $(if ($same) { "DarkGray" } else { "Yellow" })
    } elseif ($same) {
        Write-Host ("  {0,-38} identical" -f $s.Name) -ForegroundColor DarkGray
    } else {
        Invoke-Erp Put "/api/resource/$(Enc $s.Type)/$(Enc $s.Name)" @{ ($s.Field) = $body } | Out-Null
        Write-Host ("  {0,-38} UPDATED" -f $s.Name) -ForegroundColor Green
    }
}
Write-Host ""

# ── 2. The threshold report: only untagged credit offsets ─────────────
$ReportName = "RPT - Clients Exceeding Debt Threshold"
$NewQuery = @"
SELECT
    c.name as 'Customer',
    c.customer_name as 'Customer Name',
    COALESCE(c.debt_threshold_amd, 0) as 'Debt Threshold',
    COALESCE(si_sum.total_outstanding, 0) as 'Current Outstanding',
    COALESCE(pe_sum.available_credit, 0) as 'Available Credit',
    COALESCE(pe_earmarked.earmarked_credit, 0) as 'Earmarked Credit',
    (COALESCE(si_sum.total_outstanding, 0) - COALESCE(pe_sum.available_credit, 0)) as 'Net Debt',
    ((COALESCE(si_sum.total_outstanding, 0) - COALESCE(pe_sum.available_credit, 0)) - COALESCE(c.debt_threshold_amd, 0)) as 'Excess Amount'
FROM ``tabCustomer`` c
LEFT JOIN (
    SELECT customer, SUM(outstanding_amount) as total_outstanding
    FROM ``tabSales Invoice``
    WHERE docstatus = 1 AND outstanding_amount > 0
    GROUP BY customer
) si_sum ON c.name = si_sum.customer
LEFT JOIN (
    -- Only UNTAGGED credit offsets: credit carrying a dispatch_case is
    -- earmarked and task_commit_invoice will not spend it on another case.
    -- KEEP IN SYNC WITH Scheduled-debt-collection.py get_net_receivable_amd.
    SELECT party as customer, SUM(unallocated_amount) as available_credit
    FROM ``tabPayment Entry``
    WHERE docstatus = 1 AND payment_type = 'Receive' AND party_type = 'Customer'
      AND unallocated_amount > 0
      AND (dispatch_case IS NULL OR dispatch_case = '')
    GROUP BY party
) pe_sum ON c.name = pe_sum.customer
LEFT JOIN (
    -- Shown for transparency only; deliberately NOT subtracted.
    SELECT party as customer, SUM(unallocated_amount) as earmarked_credit
    FROM ``tabPayment Entry``
    WHERE docstatus = 1 AND payment_type = 'Receive' AND party_type = 'Customer'
      AND unallocated_amount > 0
      AND dispatch_case IS NOT NULL AND dispatch_case <> ''
    GROUP BY party
) pe_earmarked ON c.name = pe_earmarked.customer
WHERE
    (COALESCE(si_sum.total_outstanding, 0) - COALESCE(pe_sum.available_credit, 0)) > COALESCE(c.debt_threshold_amd, 0)
ORDER BY 'Excess Amount' DESC
"@

Write-Host "[2] $ReportName" -ForegroundColor Magenta
$rep = Get-ErpDoc "Report" $ReportName
if (-not $rep) {
    Write-Host "  NOT FOUND on server" -ForegroundColor Red
} else {
    $same = ($rep.query -replace "`r`n", "`n").TrimEnd() -eq ($NewQuery -replace "`r`n", "`n").TrimEnd()
    if ($Mode -eq "Check") {
        Write-Host ("  query {0}" -f $(if ($same) { "identical" } else { "DIFFERS - WOULD UPDATE" })) -ForegroundColor $(if ($same) { "DarkGray" } else { "Yellow" })
    } elseif ($same) {
        Write-Host "  query identical" -ForegroundColor DarkGray
    } else {
        Invoke-Erp Put "/api/resource/$(Enc 'Report')/$(Enc $ReportName)" @{ query = $NewQuery } | Out-Null
        Write-Host "  query UPDATED - now splits available vs earmarked credit" -ForegroundColor Green
    }
}
Write-Host ""

# ── 3. Retire the duplicate Director report ───────────────────────────
# Em-dash built from its code point, never typed as a literal. PowerShell 5.1
# reads a BOM-less file as ANSI, so a non-ASCII character inside a
# double-quoted string is mangled before the parser sees it -- which is a
# SYNTAX ERROR, not just corrupted text. Every other .ps1 in this folder has
# zero non-ASCII inside double quotes; that is the convention, not an accident.
$EmDash = [char]0x2014
$DupReport = "RPT $EmDash Risk $EmDash Debt Threshold Exceeded"
$WsName = "Ops $EmDash Reporting Pack"
Write-Host "[3] Retire duplicate: $DupReport" -ForegroundColor Magenta
$dup = Get-ErpDoc "Report" $DupReport
if (-not $dup) {
    Write-Host "  already gone" -ForegroundColor DarkGray
} elseif ($Mode -eq "Check") {
    Write-Host "  exists - WOULD DELETE (needs -ConfirmDeletions)" -ForegroundColor Yellow
} elseif (-not $ConfirmDeletions) {
    Write-Host "  SKIPPED - pass -ConfirmDeletions to retire it" -ForegroundColor Yellow
} else {
    # Repoint the workspace shortcut FIRST, so the shortcut never dangles. A7
    # exists partly to stop Directors seeing two answers to one question;
    # leaving a dead link would replace one confusion with another.
    #
    # THE WORKSPACE CANNOT BE SAVED UNTIL ITS PRE-EXISTING DEAD LINKS ARE FIXED.
    # Frappe validates EVERY Link row on save, so the two dangling shortcuts
    # recorded in A6 -- reports that do not exist -- block any edit to this
    # workspace at all:
    #   Row #10  RPT (Ops) Prepaid Orders Awaiting Delivery  - wrong name
    #   Row #19  RPT (Pricing) Sales Orders With Manual Rate Edits - no such report
    # That reclassifies them from cosmetic to blocking. They are repaired here
    # because there is no way to do this job without repairing them.
    $AllReports = @()
    try {
        $wcr = New-Object System.Net.WebClient
        $wcr.Encoding = [System.Text.Encoding]::UTF8
        $wcr.Headers.Add("Authorization", "token $($ApiKey):$($ApiSec)")
        $AllReports = (($wcr.DownloadString("$BaseUrl/api/resource/Report?limit_page_length=0&fields=%5B%22name%22%5D") | ConvertFrom-Json).data).name
    } catch { throw "Could not list Reports to validate workspace shortcuts: $_" }

    # A dead shortcut whose report exists under a different name is REPOINTED,
    # not deleted -- the feature works, only the link is wrong. Matched on a
    # distinctive substring so em-dash vs hyphen cannot defeat it.
    $RepairHints = @("Prepaid Orders Awaiting Delivery")

    $ws = Get-ErpDoc "Workspace" $WsName
    if ($ws) {
        $shortcuts = @()
        $repointed = 0
        $repaired = @()
        $dropped = @()
        foreach ($sc in $ws.shortcuts) {
            if ($sc.type -ne "Report") { $shortcuts += $sc; continue }
            if ($sc.link_to -eq $DupReport) {
                $sc.link_to = $ReportName
                $sc.label = "Debt Threshold Exceeded"
                $repointed++
                $shortcuts += $sc
                continue
            }
            if ($AllReports -contains $sc.link_to) { $shortcuts += $sc; continue }
            $fixed = $null
            foreach ($hint in $RepairHints) {
                if ($sc.link_to -like "*$hint*") {
                    foreach ($r in $AllReports) { if ($r -like "*$hint*") { $fixed = $r; break } }
                }
                if ($fixed) { break }
            }
            if ($fixed) {
                $repaired += ("{0} -> {1}" -f $sc.link_to, $fixed)
                $sc.link_to = $fixed
                $shortcuts += $sc
            } else {
                # No such report under any name. The shortcut cannot be kept:
                # Frappe refuses the save while it is present.
                $dropped += $sc.link_to
            }
        }
        Invoke-Erp Put "/api/resource/$(Enc 'Workspace')/$(Enc $WsName)" @{ shortcuts = $shortcuts } | Out-Null
        Write-Host ("  workspace: {0} repointed to '{1}'" -f $repointed, $ReportName) -ForegroundColor Green
        foreach ($r in $repaired) { Write-Host ("  workspace: REPAIRED dead link {0}" -f $r) -ForegroundColor Green }
        foreach ($d in $dropped) { Write-Host ("  workspace: REMOVED dead link {0} (no such report)" -f $d) -ForegroundColor Yellow }
    }
    Invoke-Erp Delete "/api/resource/$(Enc 'Report')/$(Enc $DupReport)" | Out-Null
    Write-Host "  DELETED" -ForegroundColor Green
}
Write-Host ""

if ($Mode -eq "Check") {
    Write-Host "Check complete. Re-run with -Mode Deploy [-ConfirmDeletions]." -ForegroundColor Yellow
} else {
    Write-Host "[Deploy] done. Now run:" -ForegroundColor Cyan
    Write-Host "  docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" -ForegroundColor DarkGray
    Write-Host "  then a7-verify-one-debt-definition.py" -ForegroundColor DarkGray
}
