# ==============================================================
# W8 - Advances live on the ledger (Group 11 financial tail rebuild)
#
# An advance is not a special kind of object. It is a payment that arrived
# before its invoice. W2 made it a SUBMITTED Payment Entry so the money reaches
# the general ledger; W8 removes the parallel bookkeeping that used to shadow
# it on the Dispatch Case, and records the business intent on the transaction
# itself instead.
#
# Adds:
#   Payment Entry.dispatch_case  - which case the money was paid for
#   Payment Entry.source_task    - which task recorded it (replaces the deleted
#                                  payment_history table as the audit trail)
#
# Deletes:
#   Dispatch Case.advance_payments      (Custom Field)
#   Dispatch Case Advance Payment       (child DocType, 2 rows)
#   Dispatch Case.prepaid_amount        (DocField)
#   Dispatch Case.prepaid_payment_entry (DocField)
#   Dispatch Case.total_paid_amount     (DocField)
#
# Why those three: prepaid_amount was subtracted from the invoice total ONCE, at
# Invoice Preparation completion, so an advance recorded afterwards changed it
# but nothing recomputed outstanding -- the case then showed a balance the
# ledger disagreed with. prepaid_payment_entry held a single link, so a second
# advance for the same case silently pointed at only the latest.
# total_paid_amount was written by no code at all; its only reference anywhere
# was a client-side hide list.
#
# Also fixes RPT - Prepaid Orders Awaiting Delivery, which has never returned a
# row: it sums Payment Entry Reference.reference_name (a Sales Invoice) and
# joins it to Dispatch Case.name, which can never match, so its
# COALESCE(total_advance,0) > 0 filter excluded everything. It now reads
# Payment Entry.dispatch_case.
#
# TEST ONLY. Credentials read from deploy/test/export.ps1.
#
#   ... -Mode Check
#   ... -Mode Deploy                    (code + report, no schema deletions)
#   ... -Mode Deploy -ConfirmDeletions  (also deletes the fields above)
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

Write-Host "W8 advances on the ledger -> $BaseUrl  [Mode=$Mode, ConfirmDeletions=$($ConfirmDeletions.IsPresent)]" -ForegroundColor Cyan
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
    # -Encoding UTF8 is REQUIRED: PowerShell 5.1 reads BOM-less files as ANSI,
    # mangling non-ASCII before upload.
    $raw = Get-Content $Path -Raw -Encoding UTF8
    $marker = if ($Path -like "*.js") { "// ---" } else { "# ---" }
    $i = $raw.IndexOf($marker)
    if ($i -lt 0) { return $raw }
    return $raw.Substring($i + $marker.Length).TrimStart("`r", "`n")
}

# ── 1. Payment Entry intent fields ────────────────────────────────────
$PeFields = @(
    @{ Name = "Payment Entry-dispatch_case"; fieldname = "dispatch_case"; label = "Dispatch Case"
        fieldtype = "Link"; options = "Dispatch Case"; insert_after = "party_name"
        description = "Which operational case this money was paid for. Business intent, recorded on the transaction." },
    @{ Name = "Payment Entry-source_task"; fieldname = "source_task"; label = "Recorded From Task"
        fieldtype = "Link"; options = "Task"; insert_after = "dispatch_case"
        description = "The task this payment was recorded from. Audit trail, replacing the deleted payment_history table." }
)

Write-Host "[1] Payment Entry intent fields" -ForegroundColor Magenta
foreach ($f in $PeFields) {
    $existing = Get-ErpDoc "Custom Field" $f.Name
    if ($Mode -eq "Check") {
        Write-Host ("  {0,-34} {1}" -f $f.fieldname, $(if ($existing) { "exists" } else { "WOULD CREATE" })) -ForegroundColor $(if ($existing) { "DarkGray" } else { "Yellow" })
    } elseif (-not $existing) {
        Invoke-Erp Post "/api/resource/$(Enc 'Custom Field')" @{
            doctype = "Custom Field"; dt = "Payment Entry"; label = $f.label
            fieldname = $f.fieldname; fieldtype = $f.fieldtype; options = $f.options
            insert_after = $f.insert_after; read_only = 1; description = $f.description
        } | Out-Null
        Write-Host ("  {0,-34} CREATED" -f $f.fieldname) -ForegroundColor Green
    } else {
        Write-Host ("  {0,-34} exists" -f $f.fieldname) -ForegroundColor DarkGray
    }
}

# ── 2. Server scripts ─────────────────────────────────────────────────
$ServerScripts = @(
    @{ Name = "Task-after-save-advance-payment"; File = "server\Task-after-save-advance-payment.py"; Ref = "Task"; Event = "After Save"; Type = "DocType Event" },
    @{ Name = "Task-before-save-payment-recording"; File = "server\Task-before-save-payment-recording.py"; Ref = "Task"; Event = "Before Save"; Type = "DocType Event" },
    @{ Name = "Dispatch-Case-before-save-access-control"; File = "server\Dispatch-Case-before-save-access-control.py"; Ref = "Dispatch Case"; Event = "Before Save"; Type = "DocType Event" },
    @{ Name = "task_debt_panel"; File = "server\task_debt_panel.py"; Type = "API" }
)

Write-Host ""
Write-Host "[2] Server scripts" -ForegroundColor Magenta
foreach ($s in $ServerScripts) {
    $path = Join-Path $WorkDir $s.File
    if (-not (Test-Path $path)) { Write-Host "  ERROR missing file: $($s.File)" -ForegroundColor Red; continue }
    $body = Read-WorkScript $path
    $existing = Get-ErpDoc "Server Script" $s.Name
    if ($Mode -eq "Check") {
        if ($existing) {
            $state = if (([string]$existing.script) -eq $body) { "identical" } else { "DIFFERS (cur=$(([string]$existing.script).Length) new=$($body.Length))" }
            Write-Host ("  {0,-42} {1}" -f $s.Name, $state)
        } else {
            Write-Host ("  {0,-42} WOULD CREATE" -f $s.Name) -ForegroundColor Yellow
        }
    } else {
        if ($existing) {
            Invoke-Erp Put "/api/resource/$(Enc 'Server Script')/$(Enc $s.Name)" @{ script = $body; disabled = 0 } | Out-Null
            Write-Host ("  {0,-42} UPDATED" -f $s.Name) -ForegroundColor Green
        } else {
            $doc = @{ doctype = "Server Script"; name = $s.Name; script_type = $s.Type; script = $body; disabled = 0 }
            if ($s.Ref) { $doc.reference_doctype = $s.Ref; $doc.doctype_event = $s.Event }
            if ($s.Type -eq "API") { $doc.api_method = $s.Name }
            Invoke-Erp Post "/api/resource/$(Enc 'Server Script')" $doc | Out-Null
            Write-Host ("  {0,-42} CREATED" -f $s.Name) -ForegroundColor Green
        }
    }
}

# ── 3. Client script ──────────────────────────────────────────────────
Write-Host ""
Write-Host "[3] Client scripts" -ForegroundColor Magenta
$cPath = Join-Path $WorkDir "client\Task-Debt-Panel.js"
$cBody = Read-WorkScript $cPath
$cExisting = Get-ErpDoc "Client Script" "Task-Debt-Panel"
if ($Mode -eq "Check") {
    $state = if ($cExisting -and ([string]$cExisting.script) -eq $cBody) { "identical" } else { "DIFFERS" }
    Write-Host ("  {0,-42} {1}" -f "Task-Debt-Panel", $state)
} else {
    Invoke-Erp Put "/api/resource/$(Enc 'Client Script')/$(Enc 'Task-Debt-Panel')" @{ script = $cBody; enabled = 1 } | Out-Null
    Write-Host ("  {0,-42} UPDATED" -f "Task-Debt-Panel") -ForegroundColor Green
}

# ── 4. Fix the prepaid report ─────────────────────────────────────────
$PrepaidQuery = @'
SELECT
    dc.name as 'Dispatch Case',
    dc.customer as 'Customer',
    dc.status as 'Status',
    dc.creation as 'Created On',
    DATEDIFF(CURDATE(), DATE(dc.creation)) as 'Age (Days)',
    COALESCE(pe_sum.total_advance, 0) as 'Advance Paid',
    COALESCE(pe_sum.still_unallocated, 0) as 'Still Unallocated',
    COALESCE(si.grand_total, 0) as 'Invoice Amount',
    COALESCE(si.outstanding_amount, 0) as 'Outstanding'
FROM `tabDispatch Case` dc
LEFT JOIN `tabSales Invoice` si ON si.dispatch_case = dc.name AND si.docstatus = 1
LEFT JOIN (
    SELECT
        pe.dispatch_case as dispatch_case,
        SUM(pe.paid_amount) as total_advance,
        SUM(pe.unallocated_amount) as still_unallocated
    FROM `tabPayment Entry` pe
    WHERE pe.docstatus = 1
      AND pe.payment_type = 'Receive'
      AND pe.dispatch_case IS NOT NULL
      AND pe.dispatch_case <> ''
    GROUP BY pe.dispatch_case
) pe_sum ON pe_sum.dispatch_case = dc.name
WHERE
    dc.docstatus = 1
    AND dc.status NOT IN ('Closed', 'Cancelled')
    AND COALESCE(pe_sum.total_advance, 0) > 0
ORDER BY DATEDIFF(CURDATE(), DATE(dc.creation)) DESC
'@

Write-Host ""
Write-Host "[4] RPT - Prepaid Orders Awaiting Delivery" -ForegroundColor Magenta
$rpt = Get-ErpDoc "Report" "RPT - Prepaid Orders Awaiting Delivery"
if (-not $rpt) {
    Write-Host "  not found -- SKIP" -ForegroundColor DarkGray
} elseif ($Mode -eq "Check") {
    $broken = ([string]$rpt.query) -match "per\.reference_name as dispatch_case"
    Write-Host ("  {0}" -f $(if ($broken) { "BROKEN (joins Sales Invoice names to case names) -- would fix" } else { "already reads Payment Entry.dispatch_case" })) -ForegroundColor $(if ($broken) { "Yellow" } else { "DarkGray" })
} else {
    Invoke-Erp Put "/api/resource/$(Enc 'Report')/$(Enc 'RPT - Prepaid Orders Awaiting Delivery')" @{ query = $PrepaidQuery } | Out-Null
    Write-Host "  UPDATED (now reads Payment Entry.dispatch_case)" -ForegroundColor Green
}

# ── 5. Schema deletions ───────────────────────────────────────────────
Write-Host ""
Write-Host "[5] Schema deletions" -ForegroundColor Magenta
$DocFieldsToDrop = @("prepaid_amount", "prepaid_payment_entry", "total_paid_amount")

if ($Mode -eq "Check" -or -not $ConfirmDeletions) {
    $acf = Get-ErpDoc "Custom Field" "Dispatch Case-advance_payments"
    Write-Host ("  Custom Field  advance_payments               {0}" -f $(if ($acf) { "WOULD DELETE" } else { "already gone" })) -ForegroundColor $(if ($acf) { "Yellow" } else { "DarkGray" })
    $adt = Get-ErpDoc "DocType" "Dispatch Case Advance Payment"
    Write-Host ("  DocType       Dispatch Case Advance Payment  {0}" -f $(if ($adt) { "WOULD DELETE" } else { "already gone" })) -ForegroundColor $(if ($adt) { "Yellow" } else { "DarkGray" })
    $dc = Get-ErpDoc "DocType" "Dispatch Case"
    foreach ($fn in $DocFieldsToDrop) {
        $present = $false
        foreach ($fld in $dc.fields) { if ($fld.fieldname -eq $fn) { $present = $true } }
        Write-Host ("  DocField      {0,-30} {1}" -f $fn, $(if ($present) { "WOULD DELETE" } else { "already gone" })) -ForegroundColor $(if ($present) { "Yellow" } else { "DarkGray" })
    }
    if ($Mode -eq "Deploy") { Write-Host "  (skipped: pass -ConfirmDeletions to apply)" -ForegroundColor Yellow }
} else {
    # Child rows first, then the field, then the doctype.
    $rows = (Invoke-Erp Get "/api/resource/$(Enc 'Dispatch Case Advance Payment')?limit_page_length=0&fields=$(Enc '["name"]')&parent=$(Enc 'Dispatch Case')").data
    foreach ($r in ($rows | Where-Object { $_ })) {
        try { Invoke-Erp Delete "/api/resource/$(Enc 'Dispatch Case Advance Payment')/$(Enc $r.name)" | Out-Null } catch {}
    }
    Write-Host ("  child rows removed: {0}" -f @($rows).Count) -ForegroundColor Green

    if (Get-ErpDoc "Custom Field" "Dispatch Case-advance_payments") {
        Invoke-Erp Delete "/api/resource/$(Enc 'Custom Field')/$(Enc 'Dispatch Case-advance_payments')" | Out-Null
        Write-Host "  Custom Field  advance_payments               DELETED" -ForegroundColor Green
    }
    if (Get-ErpDoc "DocType" "Dispatch Case Advance Payment") {
        try {
            Invoke-Erp Delete "/api/resource/$(Enc 'DocType')/$(Enc 'Dispatch Case Advance Payment')" | Out-Null
            Write-Host "  DocType       Dispatch Case Advance Payment  DELETED" -ForegroundColor Green
        } catch {
            Write-Host "  DocType       Dispatch Case Advance Payment  COULD NOT DELETE" -ForegroundColor Yellow
        }
    }

    # DocFields live on the DocType itself, so the field list is rewritten
    # without them rather than deleted individually.
    $dc = Get-ErpDoc "DocType" "Dispatch Case"
    $kept = @()
    $dropped = @()
    foreach ($fld in $dc.fields) {
        if ($DocFieldsToDrop -contains $fld.fieldname) { $dropped += $fld.fieldname } else { $kept += $fld }
    }
    if ($dropped.Count -gt 0) {
        try {
            Invoke-Erp Put "/api/resource/$(Enc 'DocType')/$(Enc 'Dispatch Case')" @{ fields = $kept } | Out-Null
            Write-Host ("  DocFields dropped: {0}" -f ($dropped -join ", ")) -ForegroundColor Green
        } catch {
            Write-Host ("  DocFields COULD NOT DROP ({0}): {1}" -f ($dropped -join ", "), $_.Exception.Message) -ForegroundColor Yellow
        }
    } else {
        Write-Host "  DocFields already gone" -ForegroundColor DarkGray
    }
}

Write-Host ""
if ($Mode -eq "Check") {
    Write-Host "Check complete. Re-run with -Mode Deploy [-ConfirmDeletions] to apply." -ForegroundColor Cyan
} else {
    Write-Host "Deploy complete." -ForegroundColor Green
    Write-Host "Now run:  docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" -ForegroundColor Yellow
}
