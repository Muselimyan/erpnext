#Requires -Version 5.1
# Deploys the Task List filtering redesign:
#   1. Updates task_list_filtered Server Script (now returns visibility metadata)
#   2. Updates Global-Mobile Back Button List Client Script (filter injection via get_args)
#   3. Clears cache
param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$ConfigPath = Join-Path (Split-Path $PSScriptRoot) "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
if ($BaseUrl -ne "https://test.erpnext.am") { throw "Refusing non-test target: $BaseUrl" }
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

function Enc([string]$s) { [uri]::EscapeDataString($s) }
function Get-ErpDoc([string]$DocType, [string]$Name) {
    try { return (Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)" -Headers $Headers -Method Get -TimeoutSec 30).data } catch { return $null }
}
function Strip-Header([string]$Content) {
    # Strip metadata header lines (# Name: ... # --- or // Name: ... // ---)
    return ($Content -replace '(?s)^(#[^\r\n]*[\r\n]+)*# ---[\r\n]*', '').TrimStart()
}
function Strip-JSHeader([string]$Content) {
    return ($Content -replace '(?s)^(//[^\r\n]*[\r\n]+)*// ---[\r\n]*', '').TrimStart()
}

$WorkDir = Join-Path (Split-Path $PSScriptRoot) "work"

Write-Host "=== Task List Filter Redesign Deployment ===" -ForegroundColor Cyan
Write-Host "Target: $BaseUrl" -ForegroundColor Yellow
Write-Host ""

# --- Read work files ---
$ServerPath = Join-Path $WorkDir "server\task_list_filtered.py"
$ClientPath = Join-Path $WorkDir "client\Global-Mobile Back Button List.js"

if (-not (Test-Path $ServerPath)) { Write-Host "ERROR: $ServerPath not found" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $ClientPath)) { Write-Host "ERROR: $ClientPath not found" -ForegroundColor Red; exit 1 }

$ServerContent = Strip-Header (Get-Content $ServerPath -Raw -Encoding UTF8)
$ClientContent = Strip-JSHeader (Get-Content $ClientPath -Raw -Encoding UTF8)

$ServerLines = ($ServerContent -split "`n").Count
$ClientLines = ($ClientContent -split "`n").Count

Write-Host "Server script: $ServerLines lines (task_list_filtered.py)" -ForegroundColor Green
Write-Host "Client script: $ClientLines lines (Global-Mobile Back Button List.js)" -ForegroundColor Green
Write-Host ""

# --- Check current state ---
$ServerDoc = Get-ErpDoc "Server Script" "task_list_filtered"
$ClientDoc = Get-ErpDoc "Client Script" "Global-Mobile Back Button List"

if (-not $ServerDoc) { Write-Host "ERROR: Server Script 'task_list_filtered' not found on server." -ForegroundColor Red; exit 1 }
if (-not $ClientDoc) { Write-Host "ERROR: Client Script 'Global-Mobile Back Button List' not found on server." -ForegroundColor Red; exit 1 }

Write-Host "Current state on server:" -ForegroundColor Gray
Write-Host "  task_list_filtered:              enabled=$($ServerDoc.disabled -eq 0)  modified=$($ServerDoc.modified)" -ForegroundColor Gray
Write-Host "  Global-Mobile Back Button List:  enabled=$($ClientDoc.enabled)  modified=$($ClientDoc.modified)" -ForegroundColor Gray
Write-Host ""

# --- Key change verification ---
$HasVisibilityResponse = $ServerContent -match 'allowed_kinds'
$HasGetArgsOverride = $ClientContent -match 'origGetArgs'
$HasLocalStorage = $ClientContent -match 'localStorage'
$NoNameInFilter = -not ($ClientContent -match 'filter_area\.add.*name.*in')
$NoFilterClear = -not ($ClientContent -match 'filter_area\.clear\(')

Write-Host "Change verification:" -ForegroundColor Yellow
Write-Host "  Server returns visibility metadata:  $HasVisibilityResponse" -ForegroundColor $(if ($HasVisibilityResponse) { "Green" } else { "Red" })
Write-Host "  Client overrides get_args:           $HasGetArgsOverride" -ForegroundColor $(if ($HasGetArgsOverride) { "Green" } else { "Red" })
Write-Host "  Client uses localStorage:            $HasLocalStorage" -ForegroundColor $(if ($HasLocalStorage) { "Green" } else { "Red" })
Write-Host "  No 'name in' filter (old pattern):   $NoNameInFilter" -ForegroundColor $(if ($NoNameInFilter) { "Green" } else { "Red" })
Write-Host "  No filter_area.clear (old pattern):  $NoFilterClear" -ForegroundColor $(if ($NoFilterClear) { "Green" } else { "Red" })
Write-Host ""

if ($Mode -eq "Check") {
    Write-Host "CHECK MODE - no changes made." -ForegroundColor Yellow
    Write-Host "Actions that -Mode Deploy would perform:" -ForegroundColor Yellow
    Write-Host "  1. Update task_list_filtered Server Script ($ServerLines lines)" -ForegroundColor White
    Write-Host "  2. Update Global-Mobile Back Button List Client Script ($ClientLines lines)" -ForegroundColor White
    Write-Host "  3. Clear cache on test server" -ForegroundColor White
    Write-Host ""
    Write-Host "Run with -Mode Deploy to apply." -ForegroundColor Yellow
    exit 0
}

# --- Deploy ---
Write-Host "DEPLOYING..." -ForegroundColor Cyan

# Step 1: Update Server Script
Write-Host "  Updating task_list_filtered Server Script..." -ForegroundColor White
$ServerBody = @{ script = $ServerContent; disabled = 0 } | ConvertTo-Json -Depth 10 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc 'Server Script')/$(Enc 'task_list_filtered')" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($ServerBody)) -TimeoutSec 60 | Out-Null
Write-Host "    Done." -ForegroundColor Green

# Step 2: Update Client Script
Write-Host "  Updating Global-Mobile Back Button List Client Script..." -ForegroundColor White
$ClientBody = @{ script = $ClientContent; enabled = 1 } | ConvertTo-Json -Depth 10 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc 'Client Script')/$(Enc 'Global-Mobile Back Button List')" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($ClientBody)) -TimeoutSec 60 | Out-Null
Write-Host "    Done." -ForegroundColor Green

# Step 3: Clear cache
Write-Host "  Clearing cache..." -ForegroundColor White
try {
    ssh -i "$env:USERPROFILE\.ssh\vps_erpnext2" root@161.97.83.156 "docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" 2>&1 | Out-Null
    Write-Host "    Done." -ForegroundColor Green
} catch {
    Write-Host "    WARNING: Could not clear cache via SSH. Clear manually:" -ForegroundColor Yellow
    Write-Host "    docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" -ForegroundColor Gray
}

# --- Verify ---
Write-Host ""
Write-Host "Verifying..." -ForegroundColor Cyan
$ServerDoc2 = Get-ErpDoc "Server Script" "task_list_filtered"
$ClientDoc2 = Get-ErpDoc "Client Script" "Global-Mobile Back Button List"

$ServerOK = ($ServerDoc2.disabled -eq 0) -and ($ServerDoc2.script -match 'allowed_kinds')
$ClientOK = ($ClientDoc2.enabled -eq 1) -and ($ClientDoc2.script -match 'origGetArgs')

Write-Host "  task_list_filtered:              updated=$ServerOK  modified=$($ServerDoc2.modified)" -ForegroundColor $(if ($ServerOK) { "Green" } else { "Red" })
Write-Host "  Global-Mobile Back Button List:  updated=$ClientOK  modified=$($ClientDoc2.modified)" -ForegroundColor $(if ($ClientOK) { "Green" } else { "Red" })

if ($ServerOK -and $ClientOK) {
    Write-Host ""
    Write-Host "SUCCESS: Task List filter redesign deployed." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Open https://test.erpnext.am/app/task (hard refresh: Ctrl+Shift+R)" -ForegroundColor White
    Write-Host "  2. Check browser console (F12) for:" -ForegroundColor White
    Write-Host "     [TaskToggle] visibility loaded {kinds: N, teams: N, admin: true/false}" -ForegroundColor Gray
    Write-Host "  3. Verify toggle bar appears with My Tasks / Open Tasks / Completed" -ForegroundColor White
    Write-Host "  4. Toggle each checkbox - list should refresh via standard Frappe pipeline" -ForegroundColor White
    Write-Host "  5. Try column filters (priority, subject) - they should work alongside toggles" -ForegroundColor White
    Write-Host "  6. Check Load More pagination works" -ForegroundColor White
    Write-Host "  7. Navigate away and back - toggles should persist (localStorage)" -ForegroundColor White
    Write-Host "  8. Run deploy\test\export.ps1 to re-export schema" -ForegroundColor White
} else {
    Write-Host ""
    Write-Host "WARNING: Verification did not match expected state." -ForegroundColor Red
}
