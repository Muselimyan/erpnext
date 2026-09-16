# ==============================================================
# W9 - The submit contract (Group 11 financial tail rebuild)
#
# THE HEADLINE FINDING
# --------------------
# Frappe runs `before_save` only when _action == "save". A SUBMITTED document
# saves with _action == "update_after_submit", which runs
# `before_update_after_submit` instead. Every Server Script registered on
# "Before Save" is therefore invisible to submitted documents.
#
# So neither the new Dispatch Case gate nor the lock-submitted script it
# replaced has ever guarded a submitted case -- and a case is submitted at order
# confirmation and then spends its whole working life submitted, while packing,
# delivery and returns mutate it. Proved with w9-probe-submitted-gate.py:
#     non-holder edits a DRAFT case      -> blocked
#     non-holder edits a SUBMITTED case  -> ALLOWED
#
# Adds Dispatch-Case-before-save-submitted-access-control, a twin registered on
# "Before Save (Submitted Document)", applying the same D17 ownership rule.
#
# It deliberately does NOT carry over lock-submitted's "only Directors may edit
# a submitted case" restriction. That rule was dormant, and enforcing it
# literally would stop Ops working: the case is submitted for the whole of
# packing, delivery and returns. What submission is meant to freeze is the
# commercial terms, which Frappe already enforces via allow_on_submit.
#
# Also in this workstream:
#   - The financial write in Task-after-save-dispatch-flow moves from
#     frappe.db.set_value to doc.save(), so changing total_invoice_amount /
#     outstanding_amount / sales_invoice produces a tabVersion row naming the
#     user. set_value writes straight to the table: no validation, no hooks, no
#     history -- on the one doctype where "who changed this figure" matters most.
#   - `Invoiced` is removed from Dispatch Case.status. No code ever set it and no
#     case has ever held it; it advertised a state the flow cannot reach.
#   - Fixes the mojibake in Dispatch-Case-after-save's task subject
#     ("Discount Approval: DC — customer"), corrupted by the ANSI upload bug that
#     W1 fixed in the deploy tooling. This is user-visible text.
#
# NOTE: allow_on_submit was already granted via Property Setters for every
# affected field, so no schema change is needed for the save to be accepted.
#
# TEST ONLY. Credentials read from deploy/test/export.ps1.
#
#   ... -Mode Check
#   ... -Mode Deploy
# ==============================================================

param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
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

Write-Host "W9 submit contract -> $BaseUrl  [Mode=$Mode]" -ForegroundColor Cyan
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
        $text = $wc.DownloadString("$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)")
        return ($text | ConvertFrom-Json).data
    } catch { return $null }
}

function Read-WorkScript { param([string]$Path)
    $raw = Get-Content $Path -Raw -Encoding UTF8
    $marker = if ($Path -like "*.js") { "// ---" } else { "# ---" }
    $i = $raw.IndexOf($marker)
    if ($i -lt 0) { return $raw }
    return $raw.Substring($i + $marker.Length).TrimStart("`r", "`n")
}

# ── 1. Server scripts ─────────────────────────────────────────────────
$ServerScripts = @(
    @{ Name = "Dispatch-Case-before-save-submitted-access-control"; File = "server\Dispatch-Case-before-save-submitted-access-control.py"; Ref = "Dispatch Case"; Event = "Before Save (Submitted Document)"; Type = "DocType Event" },
    @{ Name = "Dispatch-Case-before-save-access-control"; File = "server\Dispatch-Case-before-save-access-control.py"; Ref = "Dispatch Case"; Event = "Before Save"; Type = "DocType Event" },
    @{ Name = "Task-after-save-dispatch-flow"; File = "server\Task-after-save-dispatch-flow.py"; Ref = "Task"; Event = "After Save"; Type = "DocType Event" },
    @{ Name = "Dispatch-Case-after-save"; File = "server\Dispatch-Case-after-save.py"; Ref = "Dispatch Case"; Event = "After Save"; Type = "DocType Event" }
)

Write-Host "[1] Server scripts" -ForegroundColor Magenta
foreach ($s in $ServerScripts) {
    $path = Join-Path $WorkDir $s.File
    if (-not (Test-Path $path)) { Write-Host "  ERROR missing file: $($s.File)" -ForegroundColor Red; continue }
    $body = Read-WorkScript $path
    $existing = Get-ErpDoc "Server Script" $s.Name
    if ($Mode -eq "Check") {
        if ($existing) {
            $state = if (([string]$existing.script) -eq $body) { "identical" } else { "DIFFERS (cur=$(([string]$existing.script).Length) new=$($body.Length))" }
            Write-Host ("  {0,-52} {1}" -f $s.Name, $state)
        } else {
            Write-Host ("  {0,-52} WOULD CREATE" -f $s.Name) -ForegroundColor Yellow
        }
    } else {
        if ($existing) {
            Invoke-Erp Put "/api/resource/$(Enc 'Server Script')/$(Enc $s.Name)" @{ script = $body; disabled = 0 } | Out-Null
            Write-Host ("  {0,-52} UPDATED" -f $s.Name) -ForegroundColor Green
        } else {
            $doc = @{ doctype = "Server Script"; name = $s.Name; script_type = $s.Type; script = $body; disabled = 0
                reference_doctype = $s.Ref; doctype_event = $s.Event }
            Invoke-Erp Post "/api/resource/$(Enc 'Server Script')" $doc | Out-Null
            Write-Host ("  {0,-52} CREATED" -f $s.Name) -ForegroundColor Green
        }
    }
}

# ── 2. Remove `Invoiced` from Dispatch Case.status ────────────────────
Write-Host ""
Write-Host "[2] Dispatch Case.status options" -ForegroundColor Magenta
$dc = Get-ErpDoc "DocType" "Dispatch Case"
$statusField = $null
foreach ($f in $dc.fields) { if ($f.fieldname -eq "status") { $statusField = $f } }
if (-not $statusField) {
    Write-Host "  status field not found -- SKIP" -ForegroundColor Red
} else {
    $opts = ([string]$statusField.options) -split "`n"
    $hasInvoiced = $false
    foreach ($o in $opts) { if ($o.Trim() -eq "Invoiced") { $hasInvoiced = $true } }
    $inUse = 0
    try {
        $rows = (Invoke-Erp Get "/api/resource/$(Enc 'Dispatch Case')?limit_page_length=1&fields=$(Enc '["name"]')&filters=$(Enc '{"status":["=","Invoiced"]}')").data
        $inUse = @($rows).Count
    } catch {}
    if ($Mode -eq "Check") {
        Write-Host ("  Invoiced present={0} cases using it={1}" -f $hasInvoiced, $inUse) -ForegroundColor $(if ($hasInvoiced) { "Yellow" } else { "DarkGray" })
    } elseif (-not $hasInvoiced) {
        Write-Host "  already removed" -ForegroundColor DarkGray
    } elseif ($inUse -gt 0) {
        Write-Host ("  REFUSING: {0} case(s) still hold status Invoiced" -f $inUse) -ForegroundColor Red
    } else {
        $kept = @()
        foreach ($o in $opts) { if ($o.Trim() -ne "Invoiced") { $kept += $o } }
        $newOpts = ($kept -join "`n")
        $newFields = @()
        foreach ($f in $dc.fields) {
            if ($f.fieldname -eq "status") { $f.options = $newOpts }
            $newFields += $f
        }
        Invoke-Erp Put "/api/resource/$(Enc 'DocType')/$(Enc 'Dispatch Case')" @{ fields = $newFields } | Out-Null
        Write-Host "  Invoiced REMOVED (no code ever set it, no case ever held it)" -ForegroundColor Green
    }
}

Write-Host ""
if ($Mode -eq "Check") {
    Write-Host "Check complete. Re-run with -Mode Deploy to apply." -ForegroundColor Cyan
} else {
    Write-Host "Deploy complete." -ForegroundColor Green
    Write-Host "Now run:  docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" -ForegroundColor Yellow
}
