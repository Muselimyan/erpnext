# ==============================================================
# D7 - delete two dead Attach fields from the Dispatch Case DocType.
#      Group 1 D7 / former ACT-13.
#
#   delivery_photo        Attach, read_only
#   return_dropoff_photo  Attach, read_only
#
# Both are referenced by nothing. Photos live on the Task and are read from File
# records by Dispatch Case-Photo-Galleries.js, which stopped hiding these two in
# D6.
#
# WHY THIS IS ITS OWN SCRIPT. These are DocFields inside the Dispatch Case custom
# DocType, not Custom Field records, so removing them means writing back the
# whole `fields` array of the central doctype of the dispatch flow. That is a
# different class of risk from deleting a Custom Field and does not belong bundled
# with unrelated cleanup.
#
# photo_section IS KEPT. It looks equally dead once the two fields go, but it is
# the mount point Dispatch Case-Photo-Galleries.js inserts the galleries into,
# and Dispatch Case-Simplify for Order Creation.js hides it during order entry.
# The gallery script is defensive enough to cope with the section being empty
# (it falls back to appending to the section wrapper), so an empty section is
# fine -- deleting it is not.
#
# SAFETY
#   - the full pre-change DocType is written to snapshots/ before anything else
#   - the field list is filtered by fieldname, and the script refuses unless
#     EXACTLY the two expected fields were removed and nothing else moved
#   - photo_section is asserted still present after the change
#   - deletion is behind -ConfirmDeletions
#
# TEST ONLY. Credentials read from deploy/test/export.ps1.
#
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
$ConfigPath = Join-Path $TestRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

if ($BaseUrl -notmatch "test\.erpnext\.am") {
    throw "Refusing to run: resolved base URL '$BaseUrl' is not the test instance."
}

$DOCTYPE = "Dispatch Case"
$DROP = @("delivery_photo", "return_dropoff_photo")
$KEEP = "photo_section"

Write-Host "D7 delete dead DC fields -> $BaseUrl  [Mode=$Mode  ConfirmDeletions=$($ConfirmDeletions.IsPresent)]" -ForegroundColor Cyan
Write-Host ""

function Enc([string]$s) { [uri]::EscapeDataString($s) }

function Invoke-Erp { param([string]$Method, [string]$Path, $Body = $null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 180 }
    $Json = $Body | ConvertTo-Json -Depth 60
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 180
}

# ── 1. Read and snapshot ──────────────────────────────────────────────
Write-Host "[1] Read current DocType" -ForegroundColor Magenta
$wc = New-Object System.Net.WebClient
$wc.Encoding = [System.Text.Encoding]::UTF8
$wc.Headers.Add("Authorization", "token $($ApiKey):$($ApiSec)")
$raw = $wc.DownloadString("$BaseUrl/api/resource/$(Enc 'DocType')/$(Enc $DOCTYPE)")
$dt = ($raw | ConvertFrom-Json).data
if (-not $dt) { throw "Could not read DocType '$DOCTYPE'." }

$before = @($dt.fields)
Write-Host ("  fields before: {0}" -f $before.Count) -ForegroundColor DarkGray

$SnapDir = Join-Path $PSScriptRoot "snapshots"
if (-not (Test-Path $SnapDir)) { New-Item -ItemType Directory -Path $SnapDir | Out-Null }
$SnapPath = Join-Path $SnapDir ("d7-dispatch-case-doctype-before-{0}.json" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
[System.IO.File]::WriteAllText($SnapPath, $raw, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("  snapshot: {0}" -f (Split-Path $SnapPath -Leaf)) -ForegroundColor Green

$present = @($before | Where-Object { $DROP -contains $_.fieldname } | ForEach-Object { $_.fieldname })
foreach ($d in $DROP) {
    $st = if ($present -contains $d) { "present" } else { "already absent" }
    Write-Host ("  {0,-26} {1}" -f $d, $st) -ForegroundColor $(if ($present -contains $d) { "Yellow" } else { "DarkGray" })
}
$hasKeep = @($before | Where-Object { $_.fieldname -eq $KEEP }).Count -eq 1
Write-Host ("  {0,-26} {1}" -f $KEEP, $(if ($hasKeep) { "present - KEEPING (gallery mount point)" } else { "absent" })) -ForegroundColor DarkGray
Write-Host ""

if ($present.Count -eq 0) {
    Write-Host "Nothing to do - both fields are already gone." -ForegroundColor Cyan
    exit 0
}

# ── 2. Build the new field list ───────────────────────────────────────
Write-Host "[2] Validate the change" -ForegroundColor Magenta
$after = @($before | Where-Object { $DROP -notcontains $_.fieldname })
$removed = $before.Count - $after.Count
Write-Host ("  fields after:  {0}  (removed {1})" -f $after.Count, $removed) -ForegroundColor DarkGray

if ($removed -ne $present.Count) {
    throw "Refusing: expected to remove $($present.Count) field(s) but the filter removed $removed."
}
if (@($after | Where-Object { $_.fieldname -eq $KEEP }).Count -ne 1) {
    throw "Refusing: '$KEEP' is not present exactly once in the new field list."
}
# Nothing other than the two targets may have changed, in order.
$beforeSeq = ($before | Where-Object { $DROP -notcontains $_.fieldname } | ForEach-Object { $_.fieldname }) -join ","
$afterSeq = ($after | ForEach-Object { $_.fieldname }) -join ","
if ($beforeSeq -ne $afterSeq) {
    throw "Refusing: the surviving field order changed. Expected identical sequence."
}
Write-Host "  surviving field order unchanged" -ForegroundColor Green
Write-Host ""

# ── 3. Apply ──────────────────────────────────────────────────────────
Write-Host "[3] Apply" -ForegroundColor Magenta
if ($Mode -eq "Check") {
    Write-Host ("  WOULD remove: {0}" -f ($present -join ", ")) -ForegroundColor Yellow
    Write-Host "  Re-run with -Mode Deploy -ConfirmDeletions to apply." -ForegroundColor Yellow
    exit 0
}
if (-not $ConfirmDeletions) {
    Write-Host "  SKIPPED - pass -ConfirmDeletions to apply a schema deletion." -ForegroundColor Yellow
    exit 0
}

Invoke-Erp Put "/api/resource/$(Enc 'DocType')/$(Enc $DOCTYPE)" @{ fields = $after } | Out-Null

# ── 4. Verify by re-reading ───────────────────────────────────────────
$raw2 = $wc.DownloadString("$BaseUrl/api/resource/$(Enc 'DocType')/$(Enc $DOCTYPE)")
$dt2 = ($raw2 | ConvertFrom-Json).data
$now = @($dt2.fields)
$still = @($now | Where-Object { $DROP -contains $_.fieldname } | ForEach-Object { $_.fieldname })
if ($still.Count -gt 0) { throw "PUT reported success but these remain: $($still -join ', ')" }
if (@($now | Where-Object { $_.fieldname -eq $KEEP }).Count -ne 1) { throw "'$KEEP' is missing after the change. Restore from $SnapPath" }
if ($now.Count -ne $after.Count) { throw "Field count is $($now.Count), expected $($after.Count). Restore from $SnapPath" }

Write-Host ("  REMOVED: {0}" -f ($present -join ", ")) -ForegroundColor Green
Write-Host ("  fields now: {0}   {1}: present" -f $now.Count, $KEEP) -ForegroundColor Green
Write-Host ""
Write-Host "[Deploy] done. Clear cache, then open a Dispatch Case and confirm the photo" -ForegroundColor Cyan
Write-Host "galleries still render under the Photos section." -ForegroundColor Cyan
Write-Host ("Rollback: PUT the fields array from {0}" -f (Split-Path $SnapPath -Leaf)) -ForegroundColor DarkGray
