#Requires -Version 5.1
# Merges Task-Product Work Area + Task-Packing Checkboxes into one script.
# Updates Task-Product Work Area with merged content, disables Task-Packing Checkboxes.
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
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

function Enc([string]$s) { [uri]::EscapeDataString($s) }
function Get-ErpDoc([string]$DocType, [string]$Name) {
    try { return (Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)" -Headers $Headers -Method Get -TimeoutSec 30).data } catch { return $null }
}

Write-Host "=== Merge: Task-Product Work Area + Task-Packing Checkboxes ===" -ForegroundColor Cyan
Write-Host "Target: $BaseUrl" -ForegroundColor Yellow
Write-Host ""

# --- Check current state ---
$PWA = Get-ErpDoc "Client Script" "Task-Product Work Area"
$PC  = Get-ErpDoc "Client Script" "Task-Packing Checkboxes"

if (-not $PWA) { Write-Host "ERROR: Task-Product Work Area not found on server." -ForegroundColor Red; exit 1 }
if (-not $PC)  { Write-Host "ERROR: Task-Packing Checkboxes not found on server." -ForegroundColor Red; exit 1 }

Write-Host "Task-Product Work Area:   enabled=$($PWA.enabled)  modified=$($PWA.modified)" -ForegroundColor Gray
Write-Host "Task-Packing Checkboxes:  enabled=$($PC.enabled)  modified=$($PC.modified)" -ForegroundColor Gray
Write-Host ""

# --- Read merged script from work file ---
$WorkDir = Split-Path $PSScriptRoot -Parent
$MergedPath = Join-Path $WorkDir "work\client\Task-Product Work Area.js"
if (-not (Test-Path $MergedPath)) { Write-Host "ERROR: Merged work file not found at $MergedPath" -ForegroundColor Red; exit 1 }

$RawContent = Get-Content $MergedPath -Raw -Encoding UTF8
# Strip header lines (// Name: ... // ---)
$ScriptContent = ($RawContent -replace '(?s)^(//[^\r\n]*[\r\n]+)*// ---[\r\n]*', '').TrimStart()

$LineCount = ($ScriptContent -split "`n").Count
Write-Host "Merged script: $LineCount lines from $MergedPath" -ForegroundColor Green

if ($Mode -eq "Check") {
    Write-Host ""
    Write-Host "CHECK MODE - no changes made." -ForegroundColor Yellow
    Write-Host "Actions that -Mode Deploy would perform:" -ForegroundColor Yellow
    Write-Host "  1. Update Task-Product Work Area script content ($LineCount lines)" -ForegroundColor White
    Write-Host "  2. Disable Task-Packing Checkboxes (set enabled=0)" -ForegroundColor White
    Write-Host ""
    Write-Host "Run with -Mode Deploy to apply." -ForegroundColor Yellow
    exit 0
}

# --- Deploy ---
Write-Host ""
Write-Host "DEPLOYING..." -ForegroundColor Cyan

# Step 1: Update Task-Product Work Area with merged content
Write-Host "  Updating Task-Product Work Area script..." -ForegroundColor White
$UpdateBody = @{ script = $ScriptContent; enabled = 1 }
$Json = $UpdateBody | ConvertTo-Json -Depth 10 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc 'Task-Product Work Area')" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 60 | Out-Null
Write-Host "    Done." -ForegroundColor Green

# Step 2: Disable Task-Packing Checkboxes
Write-Host "  Disabling Task-Packing Checkboxes..." -ForegroundColor White
$DisableBody = @{ enabled = 0 }
$Json2 = $DisableBody | ConvertTo-Json -Depth 10 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc 'Task-Packing Checkboxes')" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($Json2)) -TimeoutSec 30 | Out-Null
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
$PWA2 = Get-ErpDoc "Client Script" "Task-Product Work Area"
$PC2  = Get-ErpDoc "Client Script" "Task-Packing Checkboxes"
Write-Host "  Task-Product Work Area:   enabled=$($PWA2.enabled)  modified=$($PWA2.modified)" -ForegroundColor $(if ($PWA2.enabled -eq 1) { "Green" } else { "Red" })
Write-Host "  Task-Packing Checkboxes:  enabled=$($PC2.enabled)  modified=$($PC2.modified)" -ForegroundColor $(if ($PC2.enabled -eq 0) { "Green" } else { "Red" })

if ($PWA2.enabled -eq 1 -and $PC2.enabled -eq 0) {
    Write-Host ""
    Write-Host "SUCCESS: Merge deployed. Task-Product Work Area updated, Task-Packing Checkboxes disabled." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Run deploy\test\export.ps1 to re-export schema" -ForegroundColor White
    Write-Host "  2. Test on https://test.erpnext.am:" -ForegroundColor White
    Write-Host "     - Pack task: Packed? checkboxes work" -ForegroundColor Gray
    Write-Host "     - Returns task: Returned/Lost/Used inputs work, mobile toggle works" -ForegroundColor Gray
    Write-Host "     - Restocking task: read-only table" -ForegroundColor Gray
    Write-Host "     - Invoice task: read-only table" -ForegroundColor Gray
    Write-Host "     - Barcode scan: REF + LOT two-scan workflow" -ForegroundColor Gray
    Write-Host "     - Only 3 buttons under 'Products / Dispatch Work'" -ForegroundColor Gray
    Write-Host "     - No duplicate toast on dispatch_case change" -ForegroundColor Gray
} else {
    Write-Host ""
    Write-Host "WARNING: Verification did not match expected state." -ForegroundColor Red
}
