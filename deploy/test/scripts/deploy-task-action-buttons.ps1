#Requires -Version 5.1
# ============================================================================
# Deploy — Task Form Button Redesign
# Target: TEST only (test.erpnext.am)
#
# Creates Task-Action Buttons.js (new unified script).
# Updates Task-Accept Start.js (stripped of button code).
# Updates Global-Mobile Back Button.js (skip floating circle on Task forms).
# Disables Task-Product Lines Display, Task-Create Dispatch Case Items,
#          Task-Dispatch Packing Usability (absorbed into new script).
# ============================================================================
param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

# --- Credentials (from ../export.ps1) ---
$ConfigPath = Join-Path (Split-Path $PSScriptRoot) "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }

function Get-ErpDoc([string]$DocType, [string]$Name) {
    try {
        return (Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)" -Headers $Headers -Method Get -TimeoutSec 30).data
    } catch { return $null }
}

function Put-ErpDoc([string]$DocType, [string]$Name, $Body) {
    $Json = $Body | ConvertTo-Json -Depth 20 -Compress
    return Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 60
}

function Post-ErpDoc([string]$DocType, $Body) {
    $Json = $Body | ConvertTo-Json -Depth 20 -Compress
    return (Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 60).data
}

# Read a work file and strip the metadata header (everything up to and including "// ---")
function Read-WorkScript([string]$Path) {
    $Content = Get-Content $Path -Raw -Encoding UTF8
    if ($Content -match '(?s)^.*?//\s*---\s*\r?\n') {
        $Content = $Content.Substring($Matches[0].Length)
    }
    return $Content.TrimEnd()
}

$WorkDir = Join-Path (Split-Path $PSScriptRoot) "work\client"

Write-Host "`n=== Task Form Button Redesign ===" -ForegroundColor Cyan
Write-Host "Target: $BaseUrl" -ForegroundColor Yellow
Write-Host "Mode: $Mode`n" -ForegroundColor Yellow

# ============================================================================
# Step 1: CREATE new Task-Action Buttons script
# ============================================================================
Write-Host "[1] Task-Action Buttons (CREATE/UPDATE)" -ForegroundColor Magenta
$tabFile = Join-Path $WorkDir "Task-Action Buttons.js"
$tabScript = Read-WorkScript $tabFile
$existingTAB = Get-ErpDoc "Client Script" "Task-Action Buttons"

if ($Mode -eq "Check") {
    if ($existingTAB) {
        Write-Host "  Already exists (enabled=$($existingTAB.enabled), modified=$($existingTAB.modified))" -ForegroundColor DarkGray
        $currentLen = ([string]$existingTAB.script).Length
        $newLen = $tabScript.Length
        Write-Host "  Current script length: $currentLen chars, new: $newLen chars" -ForegroundColor DarkGray
    } else {
        Write-Host "  WOULD CREATE: Task-Action Buttons" -ForegroundColor Yellow
    }
} else {
    if ($existingTAB) {
        Put-ErpDoc "Client Script" "Task-Action Buttons" @{
            script = $tabScript
            enabled = 1
        } | Out-Null
        Write-Host "  UPDATED: Task-Action Buttons" -ForegroundColor Green
    } else {
        Post-ErpDoc "Client Script" @{
            name = "Task-Action Buttons"
            dt = "Task"
            view = "Form"
            script = $tabScript
            enabled = 1
        } | Out-Null
        Write-Host "  CREATED: Task-Action Buttons" -ForegroundColor Green
    }
}

# ============================================================================
# Step 2: UPDATE Task-Accept Start (stripped of button code)
# ============================================================================
Write-Host "`n[2] Task-Accept Start (UPDATE)" -ForegroundColor Magenta
$tasFile = Join-Path $WorkDir "Task-Accept Start.js"
$tasScript = Read-WorkScript $tasFile
$existingTAS = Get-ErpDoc "Client Script" "Task-Accept Start"

if ($Mode -eq "Check") {
    if ($existingTAS) {
        $currentLen = ([string]$existingTAS.script).Length
        $newLen = $tasScript.Length
        Write-Host "  Current: $currentLen chars, New: $newLen chars (delta: $($newLen - $currentLen))" -ForegroundColor DarkGray
        if ($currentLen -gt $newLen) {
            Write-Host "  Script will shrink by $($currentLen - $newLen) chars (button code removed)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  NOT FOUND (unexpected)" -ForegroundColor Red
    }
} else {
    if (-not $existingTAS) { throw "Task-Accept Start not found on server" }
    Put-ErpDoc "Client Script" "Task-Accept Start" @{
        script = $tasScript
        enabled = 1
    } | Out-Null
    Write-Host "  UPDATED: Task-Accept Start" -ForegroundColor Green
}

# ============================================================================
# Step 3: UPDATE Global-Mobile Back Button (skip on Task forms)
# ============================================================================
Write-Host "`n[3] Global-Mobile Back Button (UPDATE)" -ForegroundColor Magenta
$gmbFile = Join-Path $WorkDir "Global-Mobile Back Button.js"
$gmbScript = Read-WorkScript $gmbFile
$existingGMB = Get-ErpDoc "Client Script" "Global-Mobile Back Button"

if ($Mode -eq "Check") {
    if ($existingGMB) {
        $hasGuard = ([string]$existingGMB.script).Contains("is_task_form")
        Write-Host "  Has Task form guard: $hasGuard" -ForegroundColor $(if ($hasGuard) { "Green" } else { "Yellow" })
    } else {
        Write-Host "  NOT FOUND (unexpected)" -ForegroundColor Red
    }
} else {
    if (-not $existingGMB) { throw "Global-Mobile Back Button not found on server" }
    Put-ErpDoc "Client Script" "Global-Mobile Back Button" @{
        script = $gmbScript
        enabled = 1
    } | Out-Null
    Write-Host "  UPDATED: Global-Mobile Back Button" -ForegroundColor Green
}

# ============================================================================
# Step 4a: UPDATE Task-Other UI Cleanup (strip inline Complete + Accept buttons)
# ============================================================================
Write-Host "`n[4a] Task-Other UI Cleanup (UPDATE)" -ForegroundColor Magenta
$touFile = Join-Path $WorkDir "Task-Other UI Cleanup.js"
$touScript = Read-WorkScript $touFile
$existingTOU = Get-ErpDoc "Client Script" "Task-Other UI Cleanup"

if ($Mode -eq "Check") {
    if ($existingTOU) {
        $hasOldBtn = ([string]$existingTOU.script).Contains("complete-task-btn")
        Write-Host "  Has old inline Complete button: $hasOldBtn" -ForegroundColor $(if ($hasOldBtn) { "Yellow" } else { "Green" })
    } else {
        Write-Host "  NOT FOUND (unexpected)" -ForegroundColor Red
    }
} else {
    if (-not $existingTOU) { throw "Task-Other UI Cleanup not found on server" }
    Put-ErpDoc "Client Script" "Task-Other UI Cleanup" @{
        script = $touScript
        enabled = 1
    } | Out-Null
    Write-Host "  UPDATED: Task-Other UI Cleanup" -ForegroundColor Green
}

# ============================================================================
# Step 4b: UPDATE Task-Account Details UI Cleanup (remove #complete-task-btn refs)
# ============================================================================
Write-Host "`n[4b] Task-Account Details UI Cleanup (UPDATE)" -ForegroundColor Magenta
$tadFile = Join-Path $WorkDir "Task-Account Details UI Cleanup.js"
$tadScript = Read-WorkScript $tadFile
$existingTAD = Get-ErpDoc "Client Script" "Task-Account Details UI Cleanup"

if ($Mode -eq "Check") {
    if ($existingTAD) {
        $hasOldRef = ([string]$existingTAD.script).Contains("complete-task-btn")
        Write-Host "  Has old #complete-task-btn refs: $hasOldRef" -ForegroundColor $(if ($hasOldRef) { "Yellow" } else { "Green" })
    } else {
        Write-Host "  NOT FOUND (unexpected)" -ForegroundColor Red
    }
} else {
    if (-not $existingTAD) { throw "Task-Account Details UI Cleanup not found on server" }
    Put-ErpDoc "Client Script" "Task-Account Details UI Cleanup" @{
        script = $tadScript
        enabled = 1
    } | Out-Null
    Write-Host "  UPDATED: Task-Account Details UI Cleanup" -ForegroundColor Green
}

# ============================================================================
# Step 6: DISABLE absorbed scripts
# ============================================================================
$disableScripts = @(
    "Task-Product Lines Display",
    "Task-Create Dispatch Case Items",
    "Task-Dispatch Packing Usability"
)

foreach ($scriptName in $disableScripts) {
    $idx = [array]::IndexOf($disableScripts, $scriptName) + 1
    Write-Host "`n[6.$idx] $scriptName (DISABLE)" -ForegroundColor Magenta
    $existing = Get-ErpDoc "Client Script" $scriptName
    if (-not $existing) {
        Write-Host "  NOT FOUND - skipping" -ForegroundColor DarkYellow
        continue
    }
    $isEnabled = [bool]$existing.enabled
    if ($Mode -eq "Check") {
        if ($isEnabled) {
            Write-Host "  Currently ENABLED - WOULD DISABLE" -ForegroundColor Yellow
        } else {
            Write-Host "  Already disabled" -ForegroundColor DarkGray
        }
    } else {
        if ($isEnabled) {
            Put-ErpDoc "Client Script" $scriptName @{ enabled = 0 } | Out-Null
            Write-Host "  DISABLED: $scriptName" -ForegroundColor Green
        } else {
            Write-Host "  Already disabled: $scriptName" -ForegroundColor DarkGray
        }
    }
}

# ============================================================================
# Step 7: Clear cache
# ============================================================================
Write-Host "`n[7] Clear cache" -ForegroundColor Magenta
if ($Mode -eq "Deploy") {
    Write-Host "  Run manually: docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" -ForegroundColor Yellow
    Write-Host "  Then run: powershell -ExecutionPolicy Bypass -File deploy\test\export.ps1" -ForegroundColor Yellow
} else {
    Write-Host "  (skipped in Check mode)" -ForegroundColor DarkGray
}

Write-Host "`n=== Done ($Mode mode) ===" -ForegroundColor Cyan
