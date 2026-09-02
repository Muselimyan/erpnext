#Requires -Version 5.1
# ============================================================================
# Deploy - Header Unification (Option B: Standard Header for All Tasks)
# Target: TEST only (test.erpnext.am)
#
# Updates Task-Action Buttons.js (generic mobile CSS + scroll-to-top added).
# Disables Task-Mobile Form Layout Fix (Pack-only header surgery).
# Disables Task-Delivery UI Fix (Delivery-only header CSS).
# Disables Task-Header Long Subject Fix (subject visibility bandaid).
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

# Read a work file and strip the metadata header (everything up to and including "// ---")
function Read-WorkScript([string]$Path) {
    $Content = Get-Content $Path -Raw -Encoding UTF8
    if ($Content -match '(?s)^.*?//\s*---\s*\r?\n') {
        $Content = $Content.Substring($Matches[0].Length)
    }
    return $Content.TrimEnd()
}

$WorkDir = Join-Path (Split-Path $PSScriptRoot) "work\client"

Write-Host ""
Write-Host "=== Header Unification - Option B ===" -ForegroundColor Cyan
Write-Host "Target: $BaseUrl" -ForegroundColor Yellow
Write-Host "Mode:   $Mode" -ForegroundColor Yellow
Write-Host ""

# ============================================================================
# Step 1: UPDATE Task-Action Buttons (generic mobile CSS + scroll-to-top)
# ============================================================================
Write-Host "[1] Task-Action Buttons (UPDATE)" -ForegroundColor Magenta
$tabFile = Join-Path $WorkDir "Task-Action Buttons.js"
$tabScript = Read-WorkScript $tabFile
$existingTAB = Get-ErpDoc "Client Script" "Task-Action Buttons"

if ($Mode -eq "Check") {
    if ($existingTAB) {
        $currentLen = ([string]$existingTAB.script).Length
        $newLen = $tabScript.Length
        $hasMobileCSS = $tabScript.Contains("task-mobile-layout-css")
        $hasScrollTop = $tabScript.Contains("tab_mobile_scroll_to_top")
        Write-Host "  Current: $currentLen chars, New: $newLen chars" -ForegroundColor DarkGray
        Write-Host "  Has generic mobile CSS: $hasMobileCSS" -ForegroundColor $(if ($hasMobileCSS) { "Green" } else { "Yellow" })
        Write-Host "  Has scroll-to-top: $hasScrollTop" -ForegroundColor $(if ($hasScrollTop) { "Green" } else { "Yellow" })
    } else {
        Write-Host "  NOT FOUND (unexpected)" -ForegroundColor Red
    }
} else {
    if (-not $existingTAB) { throw "Task-Action Buttons not found on server" }
    Put-ErpDoc "Client Script" "Task-Action Buttons" @{
        script = $tabScript
        enabled = 1
    } | Out-Null
    Write-Host "  UPDATED: Task-Action Buttons" -ForegroundColor Green
}

# ============================================================================
# Step 2: DISABLE scripts absorbed by header unification
# ============================================================================
$disableScripts = @(
    "Task-Mobile Form Layout Fix",
    "Task-Delivery UI Fix",
    "Task-Header Long Subject Fix"
)

foreach ($scriptName in $disableScripts) {
    $idx = [array]::IndexOf($disableScripts, $scriptName) + 1
    Write-Host ""
    Write-Host "[2.$idx] $scriptName (DISABLE)" -ForegroundColor Magenta
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
# Step 3: Clear cache
# ============================================================================
Write-Host ""
Write-Host "[3] Clear cache" -ForegroundColor Magenta
if ($Mode -eq "Deploy") {
    Write-Host "  Run manually: docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" -ForegroundColor Yellow
    Write-Host "  Then run: powershell -ExecutionPolicy Bypass -File deploy\test\export.ps1" -ForegroundColor Yellow
} else {
    Write-Host "  (skipped in Check mode)" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Cyan
