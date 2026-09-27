# ==============================================================
# D11 - DISPATCH CASE CANCELLATION FLOW
# Design: deploy/test/work/cancel-flow-design.md
#
# A Dispatch Case can be cancelled until its goods reach the client. Before
# that point the flow creates no invoice, so cancellation never involves
# billing, credit notes or tender quantities. If the goods have left Main they
# come back through the existing returns chain:
#
#   Return to warehouse (NEW handler)  Delivery In-Transit -> Returns
#   Returns processing / verification  existing, one guard: no invoice or
#                                      status change on a cancelled case
#   Returns restocking                 existing, unchanged
#   Write-off Approval (if a loss)     existing, one guard: no Bill Client
#
# Cancelled is final for the case and for every task on it.
#
# DEPLOY ORDER MATTERS
#   1. schema first -- the API writes the new status and the new fields
#   2. server scripts
#   3. client scripts
#   4. reports -- the aging report is fixed BEFORE its duplicate is retired,
#      and the duplicate's workspace shortcut is repointed BEFORE it is
#      deleted (Group 10 F-030: a dead link makes a workspace unsaveable)
#
# ONE-WAY DOORS (need -ConfirmDeletions): retiring the duplicate report.
#
# TEST ONLY. Credentials read from deploy/test/export.ps1.
#   ... -Mode Check
#   ... -Mode Deploy -ConfirmDeletions
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
$Config = Get-Content (Join-Path $TestRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
if ($BaseUrl -notmatch "test\.erpnext\.am") { throw "Refusing to run: '$BaseUrl' is not the test instance." }

# Em-dash from its code point: a literal non-ASCII character inside a
# double-quoted string is a SYNTAX ERROR under PowerShell 5.1 (AGENTS.md).
$EmDash = [char]0x2014
$DupAging = "RPT $EmDash Dispatch Cases $EmDash Aging (Open)"
$KeepAging = "RPT - Dispatch Case Aging"
$WsName = "Ops $EmDash Reporting Pack"

Write-Host "D11 cancel flow -> $BaseUrl  [Mode=$Mode  ConfirmDeletions=$($ConfirmDeletions.IsPresent)]" -ForegroundColor Cyan
Write-Host ""

function Enc([string]$s) { [uri]::EscapeDataString($s) }
function Invoke-Erp { param([string]$Method, [string]$Path, $Body = $null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 180 }
    $Json = $Body | ConvertTo-Json -Depth 40
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 180
}
function Get-ErpDoc { param([string]$DocType, [string]$Name)
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Encoding = [System.Text.Encoding]::UTF8
        $wc.Headers.Add("Authorization", "token $($ApiKey):$($ApiSec)")
        return (($wc.DownloadString("$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)")) | ConvertFrom-Json).data
    } catch { return $null }
}
function Read-WorkScript { param([string]$Path)
    $raw = Get-Content $Path -Raw -Encoding UTF8
    $marker = if ($Path -like "*.js") { "// ---" } else { "# ---" }
    $i = $raw.IndexOf($marker)
    if ($i -lt 0) { return $raw }
    return $raw.Substring($i + $marker.Length).TrimStart("`r", "`n")
}
function Same { param($a, $b) return (($a -replace "`r`n", "`n").TrimEnd() -eq ($b -replace "`r`n", "`n").TrimEnd()) }

# ── 1a. Cancelled on the Dispatch Case status field ───────────────────
# A Property Setter, not a rewrite of the DocType's fields array: adding one
# option should not mean PUTting the whole central doctype (the D7 lesson).
Write-Host "[1a] Dispatch Case status: add Cancelled" -ForegroundColor Magenta
$StatusOptions = @("Draft", "Awaiting Approval", "Confirmed", "Packed", "In Transit", "Delivered",
    "Awaiting Return Pickup", "Return Pickup Scheduled", "Return In Transit", "Returns Received",
    "Invoice Pending", "Payment Pending", "Closed", "Cancelled") -join "`n"
$PsName = "Dispatch Case-status-options"
$ps = Get-ErpDoc "Property Setter" $PsName
if ($ps -and (Same $ps.value $StatusOptions)) {
    Write-Host "  already present" -ForegroundColor DarkGray
} elseif ($Mode -eq "Check") {
    Write-Host "  WOULD SET options (14, ending Cancelled)" -ForegroundColor Yellow
} else {
    $body = @{ doctype_or_field = "DocField"; doc_type = "Dispatch Case"; field_name = "status"
        property = "options"; property_type = "Text"; value = $StatusOptions }
    if ($ps) { Invoke-Erp Put "/api/resource/$(Enc 'Property Setter')/$(Enc $PsName)" $body | Out-Null }
    else { $body.name = $PsName; Invoke-Erp Post "/api/resource/$(Enc 'Property Setter')" $body | Out-Null }
    Write-Host "  SET" -ForegroundColor Green
}
Write-Host ""

# ── 1b. The four cancellation fields, in their own section ────────────
# Read-only: they are written only by dispatch_case_cancel. The section is
# shown only on a cancelled case -- depends_on is structural, not the
# client-side layout patching AGENTS.md forbids.
Write-Host "[1b] Cancellation fields on Dispatch Case" -ForegroundColor Magenta
$Fields = @(
    @{ fieldname = "cancellation_section"; label = "Cancellation"; fieldtype = "Section Break"; insert_after = "notes"
        depends_on = "eval:doc.status=='Cancelled'" },
    @{ fieldname = "cancellation_reason"; label = "Cancellation Reason"; fieldtype = "Select"; insert_after = "cancellation_section"
        options = "`nCustomer cancelled`nSurgery cancelled or postponed`nItems unavailable`nDuplicate order`nEntered in error`nOther"; read_only = 1 },
    @{ fieldname = "cancelled_by"; label = "Cancelled By"; fieldtype = "Link"; options = "User"; insert_after = "cancellation_reason"; read_only = 1 },
    @{ fieldname = "cancelled_at"; label = "Cancelled At"; fieldtype = "Datetime"; insert_after = "cancelled_by"; read_only = 1 },
    @{ fieldname = "cancellation_notes"; label = "Cancellation Notes"; fieldtype = "Small Text"; insert_after = "cancelled_at"; read_only = 1 }
)
foreach ($f in $Fields) {
    $name = "Dispatch Case-" + $f.fieldname
    $existing = Get-ErpDoc "Custom Field" $name
    if ($existing) {
        Write-Host ("  {0,-24} exists" -f $f.fieldname) -ForegroundColor DarkGray
    } elseif ($Mode -eq "Check") {
        Write-Host ("  {0,-24} WOULD CREATE" -f $f.fieldname) -ForegroundColor Yellow
    } else {
        $payload = @{ doctype = "Custom Field"; dt = "Dispatch Case" }
        foreach ($k in $f.Keys) { $payload[$k] = $f[$k] }
        Invoke-Erp Post "/api/resource/$(Enc 'Custom Field')" $payload | Out-Null
        # Read back: some Frappe versions prefix custom_ onto a generated
        # fieldname. The API writes these exact names, so a prefix would make
        # every cancellation fail on its first write.
        $made = Get-ErpDoc "Custom Field" $name
        if (-not $made -or $made.fieldname -ne $f.fieldname) {
            throw ("Custom Field {0} was not created with the exact fieldname the API writes." -f $f.fieldname)
        }
        Write-Host ("  {0,-24} CREATED" -f $f.fieldname) -ForegroundColor Green
    }
}
Write-Host ""

# ── 2. Server scripts ─────────────────────────────────────────────────
Write-Host "[2] Server scripts" -ForegroundColor Magenta
$Server = @(
    @{ Name = "dispatch_case_cancel"; Type = "API"; DocType = ""; Event = "" },
    @{ Name = "Task-before-save-access-control" },
    @{ Name = "Dispatch-Case-before-save-access-control" },
    @{ Name = "Dispatch-Case-before-save-submitted-access-control" },
    @{ Name = "Task-after-save-dispatch-flow" },
    @{ Name = "Task-before-save-dispatch-gates" }
)
foreach ($s in $Server) {
    $body = Read-WorkScript (Join-Path $WorkDir ("server\" + $s.Name + ".py"))
    $e = Get-ErpDoc "Server Script" $s.Name
    if (-not $e) {
        if (-not $s.Type) { throw ("{0} is missing on the server and is not a new script." -f $s.Name) }
        if ($Mode -eq "Check") { Write-Host ("  {0,-52} WOULD CREATE" -f $s.Name) -ForegroundColor Yellow; continue }
        Invoke-Erp Post "/api/resource/$(Enc 'Server Script')" @{ name = $s.Name; script_type = $s.Type; api_method = $s.Name; script = $body; disabled = 0 } | Out-Null
        Write-Host ("  {0,-52} CREATED" -f $s.Name) -ForegroundColor Green
        continue
    }
    if (Same $e.script $body) { Write-Host ("  {0,-52} identical" -f $s.Name) -ForegroundColor DarkGray }
    elseif ($Mode -eq "Check") { Write-Host ("  {0,-52} DIFFERS" -f $s.Name) -ForegroundColor Yellow }
    else { Invoke-Erp Put "/api/resource/$(Enc 'Server Script')/$(Enc $s.Name)" @{ script = $body } | Out-Null; Write-Host ("  {0,-52} UPDATED" -f $s.Name) -ForegroundColor Green }
}
Write-Host ""

# ── 3. Client scripts ─────────────────────────────────────────────────
Write-Host "[3] Client scripts" -ForegroundColor Magenta
$Client = @(
    @{ Name = "Dispatch Case-Cancel"; Dt = "Dispatch Case"; New = $true },
    @{ Name = "Task-Field-Visibility"; Dt = "Task"; New = $false }
)
foreach ($c in $Client) {
    $body = Read-WorkScript (Join-Path $WorkDir ("client\" + $c.Name + ".js"))
    $e = Get-ErpDoc "Client Script" $c.Name
    if (-not $e) {
        if (-not $c.New) { throw ("{0} is missing on the server." -f $c.Name) }
        if ($Mode -eq "Check") { Write-Host ("  {0,-30} WOULD CREATE" -f $c.Name) -ForegroundColor Yellow; continue }
        Invoke-Erp Post "/api/resource/$(Enc 'Client Script')" @{ name = $c.Name; dt = $c.Dt; view = "Form"; enabled = 1; script = $body } | Out-Null
        Write-Host ("  {0,-30} CREATED" -f $c.Name) -ForegroundColor Green
        continue
    }
    if (Same $e.script $body) { Write-Host ("  {0,-30} identical" -f $c.Name) -ForegroundColor DarkGray }
    elseif ($Mode -eq "Check") { Write-Host ("  {0,-30} DIFFERS" -f $c.Name) -ForegroundColor Yellow }
    else { Invoke-Erp Put "/api/resource/$(Enc 'Client Script')/$(Enc $c.Name)" @{ script = $body } | Out-Null; Write-Host ("  {0,-30} UPDATED" -f $c.Name) -ForegroundColor Green }
}
Write-Host ""

# ── 4a0. Repair the aging report's corrupted FROM clause ──────────────
# This report has never run. It was deployed through a PowerShell
# double-quoted string, where backtick-t is the TAB escape, so the table
# reference `tabDispatch Case` arrived as TAB + "abDispatch Case" and every
# execution fails with a SQL syntax error. Five other reports carry the same
# corruption (recorded in Group 10); this one is repaired here because it is
# the report the cancel flow keeps and repoints the workspace to.
#
# The backtick and TAB are built from their code points. Writing them
# literally in a double-quoted string is precisely the bug being repaired.
Write-Host "[4a0] $KeepAging - repair the corrupted table reference" -ForegroundColor Magenta
$rep = Get-ErpDoc "Report" $KeepAging
if (-not $rep) { throw "$KeepAging not found." }
$Bt = [string][char]96
$Tab = [string][char]9
$Corrupt = $Tab + 'abDispatch Case dc'
$Repaired = $Bt + 'tabDispatch Case' + $Bt + ' dc'
$corruptHits = ([regex]::Matches($rep.query, [regex]::Escape($Corrupt))).Count
if ($corruptHits -eq 0) {
    Write-Host "  table reference is intact" -ForegroundColor DarkGray
} elseif ($corruptHits -ne 1) {
    throw "Expected exactly one corrupted table reference in $KeepAging, found $corruptHits. Refusing to guess."
} elseif ($Mode -eq "Check") {
    Write-Host "  CORRUPTED (TAB + 'abDispatch Case') - WOULD REPAIR" -ForegroundColor Yellow
} else {
    Invoke-Erp Put "/api/resource/$(Enc 'Report')/$(Enc $KeepAging)" @{ query = $rep.query.Replace($Corrupt, $Repaired) } | Out-Null
    $rep = Get-ErpDoc "Report" $KeepAging
    Write-Host "  REPAIRED" -ForegroundColor Green
}
Write-Host ""

# ── 4a. Fix the aging report so cancelled cases are not "open" ────────
Write-Host "[4a] $KeepAging excludes Cancelled" -ForegroundColor Magenta
$old = "dc.status != 'Closed'"
$new = "dc.status NOT IN ('Closed', 'Cancelled')"
if ($rep.query.Contains($new)) {
    Write-Host "  already excludes Cancelled" -ForegroundColor DarkGray
} else {
    $hits = ([regex]::Matches($rep.query, [regex]::Escape($old))).Count
    if ($hits -ne 1) { throw "Expected exactly one '$old' in $KeepAging, found $hits. Refusing to guess." }
    if ($Mode -eq "Check") { Write-Host "  WOULD CHANGE filter to exclude Cancelled" -ForegroundColor Yellow }
    else {
        Invoke-Erp Put "/api/resource/$(Enc 'Report')/$(Enc $KeepAging)" @{ query = $rep.query.Replace($old, $new) } | Out-Null
        Write-Host "  filter now excludes Cancelled" -ForegroundColor Green
    }
}
Write-Host ""

# ── 4b. Retire the duplicate aging report ─────────────────────────────
Write-Host "[4b] Retire duplicate: $DupAging" -ForegroundColor Magenta
$dup = Get-ErpDoc "Report" $DupAging
if (-not $dup) {
    Write-Host "  already gone" -ForegroundColor DarkGray
} elseif ($Mode -eq "Check") {
    Write-Host "  exists - WOULD repoint its shortcut, then DELETE (needs -ConfirmDeletions)" -ForegroundColor Yellow
} elseif (-not $ConfirmDeletions) {
    Write-Host "  SKIPPED - pass -ConfirmDeletions" -ForegroundColor Yellow
} else {
    # Repoint FIRST. Deleting a report and leaving its shortcut is exactly how
    # the two dead links in this workspace were created (Group 10 F-030).
    $ws = Get-ErpDoc "Workspace" $WsName
    if ($ws) {
        $moved = 0
        $shortcuts = @()
        foreach ($sc in $ws.shortcuts) {
            if ($sc.type -eq "Report" -and $sc.link_to -eq $DupAging) { $sc.link_to = $KeepAging; $moved++ }
            $shortcuts += $sc
        }
        if ($moved -gt 0) {
            Invoke-Erp Put "/api/resource/$(Enc 'Workspace')/$(Enc $WsName)" @{ shortcuts = $shortcuts } | Out-Null
            Write-Host ("  repointed {0} shortcut(s) to '{1}'" -f $moved, $KeepAging) -ForegroundColor Green
        } else {
            Write-Host "  no workspace shortcut pointed at it" -ForegroundColor DarkGray
        }
    }
    Invoke-Erp Delete "/api/resource/$(Enc 'Report')/$(Enc $DupAging)" | Out-Null
    Write-Host "  DELETED" -ForegroundColor Green
}
Write-Host ""

if ($Mode -eq "Check") { Write-Host "Check complete. Re-run with -Mode Deploy -ConfirmDeletions." -ForegroundColor Yellow }
else {
    Write-Host "[Deploy] done. Now:" -ForegroundColor Cyan
    Write-Host "  docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" -ForegroundColor DarkGray
    Write-Host "  d11-verify-cancel-flow.py, then the full regression set" -ForegroundColor DarkGray
}
