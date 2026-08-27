#Requires -Version 5.1
<#
.SYNOPSIS
    Deploys photo-related client script improvements to TEST environment.
.DESCRIPTION
    Updates 5 client scripts on test.erpnext.am:
      1. Task-Mobile Form Layout Fix   — photo delete buttons + acceptance gate
      2. Task-Other UI Cleanup          — photo delete buttons + acceptance gate
      3. Task-Account Details UI Cleanup — photo delete buttons + acceptance gate
      4. Task-Lock Unaccepted           — backup hide/show of custom photo buttons
      5. Task-Accept Start              — removed Order Entry photo code
    Each script is backed up before overwriting.
#>
Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$ConfigPath = Join-Path $PSScriptRoot "..\export.ps1"
$Config = Get-Content $ConfigPath -Raw
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$BaseUrl = "https://test.erpnext.am"
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }

$WorkDir = Join-Path $PSScriptRoot "..\work\client"

$Scripts = @(
    @{ Name = "Task-Mobile Form Layout Fix";    File = "Task-Mobile Form Layout Fix.js" },
    @{ Name = "Task-Other UI Cleanup";          File = "Task-Other UI Cleanup.js" },
    @{ Name = "Task-Account Details UI Cleanup"; File = "Task-Account Details UI Cleanup.js" },
    @{ Name = "Task-Lock Unaccepted";           File = "Task-Lock Unaccepted.js" },
    @{ Name = "Task-Accept Start";              File = "Task-Accept Start.js" }
)

Write-Host "=== Deploy photo improvements to TEST ===" -ForegroundColor Cyan
Write-Host "Target: $BaseUrl" -ForegroundColor Yellow
Write-Host ""

$BackupDir = Join-Path $PSScriptRoot ("_backup_photo_improvements_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

$success = 0
$failed = 0

foreach ($s in $Scripts) {
    $scriptName = $s.Name
    $filePath = Join-Path $WorkDir $s.File

    Write-Host "--- $scriptName ---" -ForegroundColor Cyan

    if (!(Test-Path $filePath)) {
        Write-Host "  ERROR: File not found: $filePath" -ForegroundColor Red
        $failed++
        continue
    }

    # Read the .js file, skip the header comment lines (Name/DocType/Enabled/---)
    $allLines = Get-Content $filePath -Encoding UTF8
    $startIdx = 0
    foreach ($line in $allLines) {
        if ($line -match '^\s*//' -or $line -match '^\s*$') { $startIdx++ } else { break }
    }
    $newScript = ($allLines[$startIdx..($allLines.Length - 1)] -join "`n")

    # Backup existing
    $existing = $null
    try {
        $existing = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $scriptName)?fields=[`"name`",`"script`",`"enabled`"]" -Headers $Headers -Method Get -TimeoutSec 30
    } catch {}

    if ($existing) {
        $backupFile = Join-Path $BackupDir ($s.File)
        $existing.data.script | Set-Content -Path $backupFile -Encoding UTF8
        Write-Host "  Backed up existing to: $backupFile" -ForegroundColor DarkGray

        $body = @{ enabled = 1; script = $newScript } | ConvertTo-Json -Depth 10 -Compress
        try {
            Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $scriptName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
            Write-Host "  Updated successfully" -ForegroundColor Green
            $success++
        } catch {
            Write-Host "  ERROR updating: $_" -ForegroundColor Red
            $failed++
        }
    } else {
        Write-Host "  Script not found on server, creating new..." -ForegroundColor Yellow
        $body = @{
            doctype = "Client Script"
            name = $scriptName
            dt = "Task"
            view = "Form"
            enabled = 1
            script = $newScript
        } | ConvertTo-Json -Depth 10 -Compress
        try {
            Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
            Write-Host "  Created successfully" -ForegroundColor Green
            $success++
        } catch {
            Write-Host "  ERROR creating: $_" -ForegroundColor Red
            $failed++
        }
    }
}

Write-Host ""
Write-Host "=== Done: $success updated, $failed failed ===" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
Write-Host "Backups in: $BackupDir" -ForegroundColor DarkGray
Write-Host "Hard-refresh the browser to pick up the changes." -ForegroundColor Yellow
