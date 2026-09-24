# ==============================================================
# D1 - Restore Stock Entry validation across the dispatch flow.
#      Closes Group 11 item A2 and Group 1 ACT-05/ACT-06.
#
# Updates two Server Scripts:
#   Task-after-save-dispatch-flow     create_se loses the `strict` parameter and
#                                     all three bypasses; the three lost/damaged
#                                     call sites drop their trailing argument;
#                                     the write-off Bin check keeps its better
#                                     error message but its comment no longer
#                                     claims A2 is open
#   Task-before-save-dispatch-gates   client_location_warehouse is required on
#                                     EVERY order, not only when returns are
#                                     expected
#
# WHAT ignore_validate ACTUALLY DID. It skips Stock Entry.validate() wholesale,
# and that includes set_basic_rate -- so a Material Transfer arrived at its
# destination valued at ZERO regardless of the source value. Main -> Delivery
# In-Transit destroyed valuation on the first hop, every later hop inherited
# zero, consumption posted zero COGS, and the restock pushed zero-valued stock
# back into Main where it dragged the moving average down on every returns
# cycle. It also let missing warehouses and insufficient stock through, so
# entries submitted successfully having posted nothing.
#
# WHY REMOVING IT IS SAFE. create_se already supplies the fields validate()
# would have filled in -- transfer_qty, uom, stock_uom, conversion_factor. That
# is what made the flag look load-bearing. Batch and serial tracking are
# globally disabled on test (disable_all_item_batch_serial_for_now), so strict
# mode will not demand batch numbers either.
#
# NO DATA MIGRATION. Test data is synthetic and is deliberately not reconciled.
# D0 measured the consequence: 77 cases hold stock in transit warehouses, but 76
# of them already cannot move -- 61 have a blank client warehouse and 15 point
# at Main. They were stuck before this change and stay stuck after it. New cases
# flow correctly. 13 items sit at negative stock in Main; avoid those in
# verification (d1-verify picks from the 40 healthy ones).
#
# KNOWN LIMIT: 372 pre-existing Stock Entries carry warehouse-less rows (172
# Material Issues that posted nothing, 200 one-sided Material Transfers that
# posted stock into or out of nowhere). This change stops new ones being
# created. It does not repair the old ones.
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

Write-Host "D1 restore stock validation -> $BaseUrl  [Mode=$Mode]" -ForegroundColor Cyan
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

# ── 0. Pre-flight ─────────────────────────────────────────────────────
# The lost/damaged movements already run validated. If the warehouse they use
# is missing, this change turns a silent no-op into a hard failure, so confirm
# it is there before removing the safety net everywhere else.
Write-Host "[0] Pre-flight" -ForegroundColor Magenta
$ldwh = Get-ErpDoc "Warehouse" "Lost & Damaged - Inmed"
if (-not $ldwh) {
    throw "Warehouse 'Lost & Damaged - Inmed' does not exist. Deploy w12 before removing the validation bypasses."
}
Write-Host ("  {0,-46} {1}" -f "Lost & Damaged - Inmed", "present") -ForegroundColor Green
$mainwh = Get-ErpDoc "Warehouse" "Main - Inmed"
if (-not $mainwh) { throw "Warehouse 'Main - Inmed' does not exist." }
Write-Host ("  {0,-46} {1}" -f "Main - Inmed", "present") -ForegroundColor Green
Write-Host ""

# ── 1. Server Scripts ─────────────────────────────────────────────────
Write-Host "[1] Server Scripts" -ForegroundColor Magenta

$Scripts = @(
    "Task-after-save-dispatch-flow",
    "Task-before-save-dispatch-gates"
)

$changed = 0
foreach ($name in $Scripts) {
    $path = Join-Path $WorkDir "server\$name.py"
    if (-not (Test-Path $path)) { throw "Work file not found: $path" }
    $local = Normalize (Read-WorkScript $path)
    $doc = Get-ErpDoc "Server Script" $name
    if (-not $doc) { throw "Server Script '$name' does not exist on $BaseUrl. This script updates, it does not create." }
    $remote = Normalize $doc.script

    # Assert the intent actually landed in the work file before uploading it.
    #
    # Strip comments first. These three names legitimately appear in the prose
    # that explains their removal, and an assertion that cannot tell code from a
    # comment would block the very change it exists to protect.
    $codeOnly = (($local -split "`n") | ForEach-Object { ($_ -split "#", 2)[0] }) -join "`n"
    $bad = @()
    if ($codeOnly -match "ignore_validate") { $bad += "ignore_validate" }
    if ($codeOnly -match "ignore_stock_validation") { $bad += "ignore_stock_validation" }
    if ($codeOnly -match "allow_zero_valuation_rate") { $bad += "allow_zero_valuation_rate" }
    if ($name -eq "Task-after-save-dispatch-flow") {
        if ($bad.Count -gt 0) {
            throw "Refusing to deploy '$name': code still contains $($bad -join ', '). The whole point of D1 is their removal."
        }
        if ($codeOnly -match "def create_se\([^)]*strict") {
            throw "Refusing to deploy '$name': create_se still takes a 'strict' parameter. D1 removes the conditional entirely."
        }
    }

    if ($local -eq $remote) {
        Write-Host ("  {0,-46} SAME" -f $name) -ForegroundColor DarkGray
        continue
    }
    $changed++
    if ($Mode -eq "Check") {
        Write-Host ("  {0,-46} DIFFERS (local {1} ch / server {2} ch)" -f $name, $local.Length, $remote.Length) -ForegroundColor Yellow
        # Show the bypass state on each side -- the whole point of D1. Compare
        # code only: the local file mentions these names in the comments that
        # explain their removal, so an un-stripped comparison reads backwards.
        $remoteCode = (($remote -split "`n") | ForEach-Object { ($_ -split "#", 2)[0] }) -join "`n"
        foreach ($flag in @("ignore_validate", "ignore_stock_validation", "allow_zero_valuation_rate")) {
            $rv = if ($remoteCode -match $flag) { "present" } else { "absent" }
            $lv = if ($codeOnly -match $flag) { "present" } else { "absent" }
            if ($rv -ne $lv) {
                Write-Host ("      {0,-28} server={1,-8} local={2}" -f $flag, $rv, $lv) -ForegroundColor Yellow
            }
        }
    } else {
        Invoke-Erp Put "/api/resource/$(Enc 'Server Script')/$(Enc $name)" @{ script = (Read-WorkScript $path) } | Out-Null
        Write-Host ("  {0,-46} UPDATED" -f $name) -ForegroundColor Green
    }
}

Write-Host ""
if ($Mode -eq "Check") {
    Write-Host "[Check] $changed script(s) would be updated. Re-run with -Mode Deploy to apply." -ForegroundColor Cyan
} else {
    Write-Host "[Deploy] $changed script(s) updated." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Clear the cache, then verify:" -ForegroundColor Yellow
    Write-Host "  ssh -i `$env:USERPROFILE\.ssh\vps_erpnext2 root@161.97.83.156 ``" -ForegroundColor DarkGray
    Write-Host "    `"docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache`"" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Get-Content deploy\test\deploy\group-1-dispatch-operational\d1-verify-stock-validation.py | ``" -ForegroundColor DarkGray
    Write-Host "    ssh -i `$env:USERPROFILE\.ssh\vps_erpnext2 root@161.97.83.156 ``" -ForegroundColor DarkGray
    Write-Host "      `"docker exec -i frappe-test-backend-1 bench --site test.erpnext.am console`"" -ForegroundColor DarkGray
}
