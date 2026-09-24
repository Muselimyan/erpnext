# ==============================================================
# D9 - remove pre-launch overrides. Group 1 D9.
#
# Changes:
#   Stock Settings.allow_negative_stock   1 -> 0
#
# WHY. D1 removed create_se's ignore_stock_validation, which restored ERPNext's
# own check -- but a check cannot overrule a setting that says the thing it
# checks for is permitted. With allow_negative_stock = 1, ERPNext has no
# objection to raise, so an overdraw still posts. Verified before this change: a
# Pack of 999,999 against a bin holding 52 submitted successfully.
#
# EXISTING RECORDS ARE NOT REPAIRED, by decision -- test data is disposable. 13
# bins in Main - Inmed are already negative (-415 units). After this change, any
# operation drawing on those 13 items FAILS until someone corrects them. That is
# the intended behaviour, not a side effect: the setting exists to make it fail.
#
# ── The other pre-launch override, NOT changed here ──────────────────
#
# Batch, serial and expiry tracking are switched OFF on every Item. Two API
# scripts did it and both are still deployed and callable:
#
#   disable_all_item_batch_serial_for_now   clears has_batch_no / has_serial_no /
#                                           has_expiry_date on ALL items
#   perm_disable_batch_expiry_dbset         same, for a named list
#
# Turning tracking back on is NOT a flip of a switch, and doing it blind would
# break packing. With batch tracking enabled, the now-strict create_se requires
# batch_no on every Stock Entry row -- and dispatch_case_packing_scan only
# captures a batch when GS1 parsing succeeds. Any item scanned by a plain
# barcode, or keyed in, would produce a row with no batch and the movement would
# be refused.
#
# For a medical device distributor this is the most consequential override of
# the set -- batch and expiry ARE the recall traceability mechanism -- so it
# needs a decision and a plan, not a toggle. Raised separately.
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
$ConfigPath = Join-Path $TestRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

if ($BaseUrl -notmatch "test\.erpnext\.am") {
    throw "Refusing to run: resolved base URL '$BaseUrl' is not the test instance."
}

Write-Host "D9 remove pre-launch overrides -> $BaseUrl  [Mode=$Mode]" -ForegroundColor Cyan
Write-Host ""

function Enc([string]$s) { [uri]::EscapeDataString($s) }

function Invoke-Erp { param([string]$Method, [string]$Path, $Body = $null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 180 }
    $Json = $Body | ConvertTo-Json -Depth 40
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 180
}

# ── 1. allow_negative_stock ───────────────────────────────────────────
Write-Host "[1] Stock Settings" -ForegroundColor Magenta
$ss = (Invoke-Erp Get "/api/resource/$(Enc 'Stock Settings')/$(Enc 'Stock Settings')").data
$cur = [int]$ss.allow_negative_stock
Write-Host ("  allow_negative_stock currently: {0}" -f $cur) -ForegroundColor $(if ($cur -eq 1) { "Yellow" } else { "DarkGray" })

if ($cur -eq 0) {
    Write-Host "  already 0 - nothing to do" -ForegroundColor DarkGray
} elseif ($Mode -eq "Check") {
    Write-Host "  WOULD SET to 0" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Impact: operations drawing on the 13 already-negative items in Main - Inmed" -ForegroundColor Yellow
    Write-Host "  will begin to FAIL. That is the point of the setting." -ForegroundColor Yellow
} else {
    Invoke-Erp Put "/api/resource/$(Enc 'Stock Settings')/$(Enc 'Stock Settings')" @{ allow_negative_stock = 0 } | Out-Null
    $after = [int]((Invoke-Erp Get "/api/resource/$(Enc 'Stock Settings')/$(Enc 'Stock Settings')").data.allow_negative_stock)
    if ($after -ne 0) { throw "Set allow_negative_stock=0 but it reads back as $after." }
    Write-Host "  SET to 0" -ForegroundColor Green
}
Write-Host ""

# ── 2. Report the override utilities (not removed here) ───────────────
Write-Host "[2] Override utilities still deployed (reported, not changed)" -ForegroundColor Magenta
foreach ($n in @("disable_all_item_batch_serial_for_now", "perm_disable_batch_expiry_dbset")) {
    try {
        $s = (Invoke-Erp Get "/api/resource/$(Enc 'Server Script')/$(Enc $n)").data
        Write-Host ("  {0,-42} disabled={1}" -f $n, $s.disabled) -ForegroundColor Yellow
    } catch {
        Write-Host ("  {0,-42} absent" -f $n) -ForegroundColor DarkGray
    }
}
Write-Host "  These are one-shot utilities. Leaving them callable means the override" -ForegroundColor DarkGray
Write-Host "  can be silently re-applied. Retiring them belongs with the decision to" -ForegroundColor DarkGray
Write-Host "  re-enable batch/serial tracking - see this script's header." -ForegroundColor DarkGray
Write-Host ""

if ($Mode -eq "Check") {
    Write-Host "[Check] Re-run with -Mode Deploy to apply." -ForegroundColor Cyan
} else {
    Write-Host "[Deploy] done. Verify with d9-verify-negative-stock.py." -ForegroundColor Cyan
}
