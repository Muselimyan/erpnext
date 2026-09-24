# ==============================================================
# D2 - Endpoint authorization and row identity. Closes Group 1 ACT-01/02/03/09.
#
# Server Scripts:
#   dispatch_case_packing_scan          asserts an accepted Pack task
#   task_mark_item_packed               asserts kind; addresses rows by name
#   task_mark_items_packed_batch        explicit mode instead of inference;
#                                       addresses rows by name
#   task_update_return_item_quantities  addresses rows by name
#   task_remove_dispatch_product        gains the lifecycle guard its two
#                                       siblings already had
#
# Client Script:
#   Task-Product Work Area              sends row_name instead of item_idx from
#                                       the returns and packing renderers
#
# WHY KIND MATTERS. The old check asked only "do you hold an accepted, open task
# on this case". Multiple open tasks per case is normal BY DESIGN -- returns
# inspection fans out to Write-off Approval, Invoice preparation and Returns
# restocking simultaneously -- so the driver on Delivery, or the accountant on
# Invoice Preparation, satisfied it and could write the packing record. That
# record is the evidence that the right lot and expiry went into the box.
#
# The Dispatch Case gate stays coarse ON PURPOSE. It asks only whether the user
# holds any accepted task on the case, because order entry, packing and returns
# all legitimately write case_items and the document cannot know which is valid.
# Kind-specific authority belongs in the endpoint. Do not "fix" the DC gate.
#
# BREAKING CHANGE. item_idx and packed_indices are no longer accepted. A caller
# sending them is refused with an explanatory error rather than quietly served,
# so the fragile path cannot survive unnoticed. Known callers:
#   Task-Product Work Area.js   updated in this deploy
#   Task-Packing Checkboxes.js  DISABLED - would need updating before re-enabling
#   task_mark_items_packed_batch has NO client caller at all; it is hardened
#   here because it remains directly callable, and is a candidate for removal.
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

Write-Host "D2 endpoint authorization -> $BaseUrl  [Mode=$Mode]" -ForegroundColor Cyan
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

function Normalize([string]$s) {
    if ($null -eq $s) { return "" }
    return ($s -replace "`r`n", "`n").Trim()
}

function Strip-Comments { param([string]$s, [string]$Kind)
    # Assertions must read code, not the prose that explains a change. A check
    # that cannot tell the two apart blocks the very edit it protects -- this
    # already happened once in D1.
    $mark = if ($Kind -eq "js") { "//" } else { "#" }
    return ((($s -split "`n") | ForEach-Object { ($_ -split [regex]::Escape($mark), 2)[0] }) -join "`n")
}

# ── 1. Server Scripts ─────────────────────────────────────────────────
Write-Host "[1] Server Scripts" -ForegroundColor Magenta

# name -> tokens that MUST be present in code after this change
$Expect = @{
    "dispatch_case_packing_scan"          = @('Pack / prepare items')
    "task_mark_item_packed"               = @('Pack / prepare items', 'row_name')
    "task_mark_items_packed_batch"        = @('MODE_KIND', 'row_names')
    "task_update_return_item_quantities"  = @('row_name', 'Returns processing / verification')
    "task_remove_dispatch_product"        = @('docstatus', 'Awaiting Approval')
}

$changed = 0
foreach ($name in $Expect.Keys | Sort-Object) {
    $path = Join-Path $WorkDir "server\$name.py"
    if (-not (Test-Path $path)) { throw "Work file not found: $path" }
    $localRaw = Read-WorkScript $path
    $local = Normalize $localRaw
    $code = Strip-Comments $local "py"
    $missing = @()
    foreach ($tok in $Expect[$name]) { if ($code -notmatch [regex]::Escape($tok)) { $missing += $tok } }
    if ($missing.Count -gt 0) {
        throw "Refusing to deploy '$name': work file is missing expected code token(s): $($missing -join ', ')"
    }
    $doc = Get-ErpDoc "Server Script" $name
    if (-not $doc) { throw "Server Script '$name' does not exist on $BaseUrl. This script updates, it does not create." }
    if ($local -eq (Normalize $doc.script)) {
        Write-Host ("  {0,-38} SAME" -f $name) -ForegroundColor DarkGray
        continue
    }
    $changed++
    if ($Mode -eq "Check") {
        Write-Host ("  {0,-38} DIFFERS" -f $name) -ForegroundColor Yellow
    } else {
        Invoke-Erp Put "/api/resource/$(Enc 'Server Script')/$(Enc $name)" @{ script = $localRaw } | Out-Null
        Write-Host ("  {0,-38} UPDATED" -f $name) -ForegroundColor Green
    }
}

# ── 2. Client Script ──────────────────────────────────────────────────
Write-Host ""
Write-Host "[2] Client Script" -ForegroundColor Magenta
$cname = "Task-Product Work Area"
$cpath = Join-Path $WorkDir "client\$cname.js"
if (-not (Test-Path $cpath)) { throw "Work file not found: $cpath" }
$clocalRaw = Read-WorkScript $cpath
$clocal = Normalize $clocalRaw
$ccode = Strip-Comments $clocal "js"
if ($ccode -match "item_idx") {
    throw "Refusing to deploy '$cname': client code still sends item_idx. The server no longer accepts it."
}
if ($ccode -notmatch "row_name:") {
    throw "Refusing to deploy '$cname': client code does not send row_name."
}
$cdoc = Get-ErpDoc "Client Script" $cname
if (-not $cdoc) { throw "Client Script '$cname' does not exist on $BaseUrl." }
if ($clocal -eq (Normalize $cdoc.script)) {
    Write-Host ("  {0,-38} SAME" -f $cname) -ForegroundColor DarkGray
} else {
    $changed++
    if ($Mode -eq "Check") {
        Write-Host ("  {0,-38} DIFFERS" -f $cname) -ForegroundColor Yellow
    } else {
        Invoke-Erp Put "/api/resource/$(Enc 'Client Script')/$(Enc $cname)" @{ script = $clocalRaw } | Out-Null
        Write-Host ("  {0,-38} UPDATED" -f $cname) -ForegroundColor Green
    }
}

Write-Host ""
if ($Mode -eq "Check") {
    Write-Host "[Check] $changed document(s) would be updated. Re-run with -Mode Deploy to apply." -ForegroundColor Cyan
} else {
    Write-Host "[Deploy] $changed document(s) updated." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Clear the cache, then verify:" -ForegroundColor Yellow
    Write-Host "  ssh -i `$env:USERPROFILE\.ssh\vps_erpnext2 root@161.97.83.156 ``" -ForegroundColor DarkGray
    Write-Host "    `"docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache`"" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Get-Content deploy\test\deploy\group-1-dispatch-operational\d2-verify-endpoint-authorization.py | ``" -ForegroundColor DarkGray
    Write-Host "    ssh -i `$env:USERPROFILE\.ssh\vps_erpnext2 root@161.97.83.156 ``" -ForegroundColor DarkGray
    Write-Host "      `"docker exec -i frappe-test-backend-1 bench --site test.erpnext.am console`"" -ForegroundColor DarkGray
}
