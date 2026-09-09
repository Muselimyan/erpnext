#Requires -Version 5.1
# ============================================================================
# Deploy — Product Section Phase B (Inline Order Items Editor)
# Target: TEST only (test.erpnext.am)
#
# Creates/updates server scripts:
#   1. task_update_dispatch_product (NEW API)
#   2. task_remove_dispatch_product (NEW API)
#   3. task_add_dispatch_product    (UPDATE — add discount_pct)
#
# Updates client script:
#   4. Task-Product Work Area.js    (inline editor)
#
# Run with -Mode Check first to preview changes.
# Run with -Mode Deploy to apply.
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
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }

# --- REST helpers ---
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

function Read-ServerScript([string]$Path) {
    $Content = Get-Content $Path -Raw -Encoding UTF8
    $lines = $Content -split "`n"
    $startIdx = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq "# ---") { $startIdx = $i + 1; break }
    }
    return ($lines[$startIdx..($lines.Count - 1)] -join "`n").TrimEnd()
}

function Read-WorkScript([string]$Path) {
    $Content = Get-Content $Path -Raw -Encoding UTF8
    if ($Content -match '(?s)^.*?//\s*---\s*\r?\n') {
        $Content = $Content.Substring($Matches[0].Length)
    }
    return $Content.TrimEnd()
}

$WorkDir = Join-Path (Split-Path $PSScriptRoot) "work"

Write-Host "`n=== Product Section Phase B ===" -ForegroundColor Cyan
Write-Host "Target: $BaseUrl" -ForegroundColor Yellow
Write-Host "Mode:   $Mode`n" -ForegroundColor Yellow

# ============================================================================
# Step 1: Server Scripts — CREATE/UPDATE
# ============================================================================
Write-Host "[1] Server Scripts" -ForegroundColor Magenta

$NewServerScripts = @(
    @{ name = "task_update_dispatch_product"; file = "server\task_update_dispatch_product.py" },
    @{ name = "task_remove_dispatch_product"; file = "server\task_remove_dispatch_product.py" }
)

foreach ($ss in $NewServerScripts) {
    $scriptPath = Join-Path $WorkDir $ss.file
    if (-not (Test-Path $scriptPath)) { Write-Host "  ERROR: $scriptPath not found" -ForegroundColor Red; continue }
    $scriptBody = Read-ServerScript $scriptPath
    $existing = Get-ErpDoc "Server Script" $ss.name

    if ($Mode -eq "Check") {
        if ($existing) {
            Write-Host "  $($ss.name): EXISTS (will update, $($scriptBody.Length) chars)" -ForegroundColor DarkGray
        } else {
            Write-Host "  $($ss.name): WOULD CREATE ($($scriptBody.Length) chars)" -ForegroundColor Yellow
        }
    } else {
        if ($existing) {
            Put-ErpDoc "Server Script" $ss.name @{ script = $scriptBody; disabled = 0 } | Out-Null
            Write-Host "  $($ss.name): UPDATED" -ForegroundColor Green
        } else {
            Post-ErpDoc "Server Script" @{
                doctype = "Server Script"
                name = $ss.name
                script_type = "API"
                api_method = $ss.name
                script = $scriptBody
                disabled = 0
            } | Out-Null
            Write-Host "  $($ss.name): CREATED" -ForegroundColor Green
        }
    }
}

# Update existing task_add_dispatch_product
$addPath = Join-Path $WorkDir "server\task_add_dispatch_product.py"
$addBody = Read-ServerScript $addPath
$existingAdd = Get-ErpDoc "Server Script" "task_add_dispatch_product"

if ($Mode -eq "Check") {
    if ($existingAdd) {
        Write-Host "  task_add_dispatch_product: EXISTS (will update, $($addBody.Length) chars)" -ForegroundColor DarkGray
    } else {
        Write-Host "  task_add_dispatch_product: NOT FOUND" -ForegroundColor Red
    }
} else {
    if (-not $existingAdd) { throw "Server Script 'task_add_dispatch_product' not found on server" }
    Put-ErpDoc "Server Script" "task_add_dispatch_product" @{ script = $addBody; disabled = 0 } | Out-Null
    Write-Host "  task_add_dispatch_product: UPDATED" -ForegroundColor Green
}

# ============================================================================
# Step 2: Client Script — UPDATE Task-Product Work Area
# ============================================================================
Write-Host "`n[2] Client Script" -ForegroundColor Magenta

$clientPath = Join-Path $WorkDir "client\Task-Product Work Area.js"
$clientBody = Read-WorkScript $clientPath
$existingClient = Get-ErpDoc "Client Script" "Task-Product Work Area"

if ($Mode -eq "Check") {
    if ($existingClient) {
        $currentLen = ([string]$existingClient.script).Length
        Write-Host "  Task-Product Work Area: WOULD UPDATE ($currentLen -> $($clientBody.Length) chars)" -ForegroundColor Yellow
    } else {
        Write-Host "  Task-Product Work Area: NOT FOUND on server" -ForegroundColor Red
    }
} else {
    if (-not $existingClient) { throw "Client Script 'Task-Product Work Area' not found on server" }
    Put-ErpDoc "Client Script" "Task-Product Work Area" @{
        script  = $clientBody
        enabled = 1
    } | Out-Null
    Write-Host "  Task-Product Work Area: UPDATED ($($clientBody.Length) chars)" -ForegroundColor Green
}

# --- Clear cache ---
if ($Mode -eq "Deploy") {
    Write-Host "`n[Cache] Clearing..." -ForegroundColor Magenta
    $sshKey = "$env:USERPROFILE\.ssh\vps_erpnext2"
    ssh -i $sshKey root@161.97.83.156 "docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    Write-Host "  Cache cleared" -ForegroundColor Green
}

Write-Host "`n=== Done ===" -ForegroundColor Cyan
