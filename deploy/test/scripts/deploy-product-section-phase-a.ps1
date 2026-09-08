#Requires -Version 5.1
# ============================================================================
# Deploy — Product Section Phase A (Fix visibility, labels, buttons)
# Target: TEST only (test.erpnext.am)
#
# Updates 3 client scripts:
#   1. Task-Field-Visibility.js  — scan rule, hide add fields, dynamic labels
#   2. Task-Product Work Area.js — remove header buttons, fix empty messages
#   3. Task-Action Buttons.js    — remove mobile product dropdown, suppress
#                                  dashboard comment for Order Entry
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

function Read-WorkScript([string]$Path) {
    $Content = Get-Content $Path -Raw -Encoding UTF8
    if ($Content -match '(?s)^.*?//\s*---\s*\r?\n') {
        $Content = $Content.Substring($Matches[0].Length)
    }
    return $Content.TrimEnd()
}

$WorkDir = Join-Path (Split-Path $PSScriptRoot) "work\client"

Write-Host "`n=== Product Section Phase A ===" -ForegroundColor Cyan
Write-Host "Target: $BaseUrl" -ForegroundColor Yellow
Write-Host "Mode:   $Mode`n" -ForegroundColor Yellow

# --- Scripts to update ---
$Scripts = @(
    @{ Name = "Task-Field-Visibility"; File = "Task-Field-Visibility.js" },
    @{ Name = "Task-Product Work Area"; File = "Task-Product Work Area.js" },
    @{ Name = "Task-Action Buttons";   File = "Task-Action Buttons.js" }
)

foreach ($s in $Scripts) {
    $filePath = Join-Path $WorkDir $s.File
    if (-not (Test-Path $filePath)) {
        Write-Host "  ERROR: File not found: $filePath" -ForegroundColor Red
        continue
    }
    $newScript = Read-WorkScript $filePath
    $existing = Get-ErpDoc "Client Script" $s.Name

    if ($Mode -eq "Check") {
        if ($existing) {
            $currentLen = ([string]$existing.script).Length
            $same = $currentLen -eq $newScript.Length -and $existing.script -eq $newScript
            if ($same) {
                Write-Host "  [$($s.Name)] UNCHANGED ($currentLen chars)" -ForegroundColor DarkGray
            } else {
                Write-Host "  [$($s.Name)] WOULD UPDATE ($currentLen -> $($newScript.Length) chars)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  [$($s.Name)] NOT FOUND on server" -ForegroundColor Red
        }
    } else {
        if (-not $existing) {
            Write-Host "  [$($s.Name)] NOT FOUND on server -- SKIP" -ForegroundColor Red
            continue
        }
        Put-ErpDoc "Client Script" $s.Name @{
            script  = $newScript
            enabled = 1
        } | Out-Null
        Write-Host "  [$($s.Name)] UPDATED ($($newScript.Length) chars)" -ForegroundColor Green
    }
}

# --- Clear cache ---
if ($Mode -eq "Deploy") {
    Write-Host "`n[Cache] Clearing..." -ForegroundColor Magenta
    $sshKey = "$env:USERPROFILE\.ssh\vps_erpnext2"
    ssh -i $sshKey root@161.97.83.156 "docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    Write-Host "  Cache cleared" -ForegroundColor Green
}

Write-Host "`n=== Done ===" -ForegroundColor Cyan
