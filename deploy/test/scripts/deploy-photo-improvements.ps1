#Requires -Version 5.1
<#
.SYNOPSIS
    Deploys the new Photo Gallery system + updated gates to TEST environment.
.DESCRIPTION
    Updates scripts on test.erpnext.am:
      Client Scripts (7):
        1. Task-Photo-System                — NEW: PhotoGallery, PhotoFullscreen, form handlers
        2. Task-Mobile Form Layout Fix      — photo code removed (layout only)
        3. Task-Other UI Cleanup            — photo gallery removed
        4. Task-Account Details UI Cleanup   — unchanged (Account Details deferred)
        5. Task-Lock Unaccepted             — updated: gallery mode toggle
        6. Task-Accept Start                — unchanged
        7. Order entry - barcode scanning section - hide — photo code removed
      Server Scripts (4):
        8. Task-before-save-dispatch-gates  — uses task_has_image() helper
        9. Task-after-save-dispatch-flow    — uses task_first_image_url() helper
       10. Task-before-save-policy          — uses task_has_image() helper
       11. Stock Entry-before-submit-dispatch-gate — uses task_has_image() helper
      Disabled Server Scripts:
       12. Task-before-save-return-dropoff-photo — disabled (obsolete)
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

$ClientWorkDir = Join-Path $PSScriptRoot "..\work\client"
$ServerWorkDir = Join-Path $PSScriptRoot "..\work\server"

# --- Client Scripts ---
$ClientScripts = @(
    @{ Name = "Task-Photo-System";                              File = "Task-Photo-System.js";                              DocType = "Task" },
    @{ Name = "Task-Mobile Form Layout Fix";                    File = "Task-Mobile Form Layout Fix.js";                    DocType = "Task" },
    @{ Name = "Task-Other UI Cleanup";                          File = "Task-Other UI Cleanup.js";                          DocType = "Task" },
    @{ Name = "Task-Account Details UI Cleanup";                File = "Task-Account Details UI Cleanup.js";                DocType = "Task" },
    @{ Name = "Task-Lock Unaccepted";                           File = "Task-Lock Unaccepted.js";                           DocType = "Task" },
    @{ Name = "Task-Accept Start";                              File = "Task-Accept Start.js";                              DocType = "Task" },
    @{ Name = "Order entry - barcode scanning section - hide";  File = "Order entry - barcode scanning section - hide.js";  DocType = "Task" },
    @{ Name = "Dispatch Case-Photo-Galleries";                  File = "Dispatch Case-Photo-Galleries.js";                  DocType = "Dispatch Case" },
    @{ Name = "Dispatch Case-Simplify for Order Creation";      File = "Dispatch Case-Simplify for Order Creation.js";      DocType = "Dispatch Case" }
)

# --- Server Scripts ---
$ServerScripts = @(
    @{ Name = "Task-before-save-dispatch-gates";        File = "Task-before-save-dispatch-gates.py";        DocType = "Task";        Event = "Before Save" },
    @{ Name = "Task-after-save-dispatch-flow";          File = "Task-after-save-dispatch-flow.py";          DocType = "Task";        Event = "After Save" },
    @{ Name = "Task-before-save-policy";                File = "Task-before-save-policy.py";                DocType = "Task";        Event = "Before Save" },
    @{ Name = "Stock Entry-before-submit-dispatch-gate"; File = "Stock Entry-before-submit-dispatch-gate.py"; DocType = "Stock Entry"; Event = "Before Submit" }
)

# --- Server Scripts to DISABLE ---
$DisableServerScripts = @(
    "Task-before-save-return-dropoff-photo"
)

Write-Host "=== Deploy Photo Gallery System to TEST ===" -ForegroundColor Cyan
Write-Host "Target: $BaseUrl" -ForegroundColor Yellow
Write-Host ""

$BackupDir = Join-Path $PSScriptRoot ("_backup_photo_gallery_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

$success = 0
$failed = 0

# ---- Deploy Client Scripts ----
Write-Host "--- CLIENT SCRIPTS ---" -ForegroundColor Magenta
foreach ($s in $ClientScripts) {
    $scriptName = $s.Name
    $filePath = Join-Path $ClientWorkDir $s.File

    Write-Host "  [$scriptName]" -ForegroundColor Cyan

    if (!(Test-Path $filePath)) {
        Write-Host "    ERROR: File not found: $filePath" -ForegroundColor Red
        $failed++
        continue
    }

    # Read the .js file, skip the header comment lines (// Name/DocType/Enabled/---)
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
        Write-Host "    Backed up existing" -ForegroundColor DarkGray

        $body = @{ enabled = 1; script = $newScript } | ConvertTo-Json -Depth 10 -Compress
        try {
            Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $scriptName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
            Write-Host "    Updated successfully" -ForegroundColor Green
            $success++
        } catch {
            Write-Host "    ERROR updating: $_" -ForegroundColor Red
            $failed++
        }
    } else {
        Write-Host "    Script not found on server, creating new..." -ForegroundColor Yellow
        $body = @{
            doctype = "Client Script"
            name = $scriptName
            dt = $s.DocType
            view = "Form"
            enabled = 1
            script = $newScript
        } | ConvertTo-Json -Depth 10 -Compress
        try {
            Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
            Write-Host "    Created successfully" -ForegroundColor Green
            $success++
        } catch {
            Write-Host "    ERROR creating: $_" -ForegroundColor Red
            $failed++
        }
    }
}

# ---- Deploy Server Scripts ----
Write-Host ""
Write-Host "--- SERVER SCRIPTS ---" -ForegroundColor Magenta
foreach ($s in $ServerScripts) {
    $scriptName = $s.Name
    $filePath = Join-Path $ServerWorkDir $s.File

    Write-Host "  [$scriptName]" -ForegroundColor Cyan

    if (!(Test-Path $filePath)) {
        Write-Host "    ERROR: File not found: $filePath" -ForegroundColor Red
        $failed++
        continue
    }

    # Read the .py file, skip the header comment lines (# Name/Type/DocType/Event/Disabled/---)
    $allLines = Get-Content $filePath -Encoding UTF8
    $startIdx = 0
    foreach ($line in $allLines) {
        if ($line -match '^\s*#' -or $line -match '^\s*$') { $startIdx++ } else { break }
    }
    $newScript = ($allLines[$startIdx..($allLines.Length - 1)] -join "`n")

    # Backup existing
    $existing = $null
    try {
        $existing = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script/$(Enc $scriptName)?fields=[`"name`",`"script`",`"disabled`"]" -Headers $Headers -Method Get -TimeoutSec 30
    } catch {}

    if ($existing) {
        $backupFile = Join-Path $BackupDir ($s.File)
        $existing.data.script | Set-Content -Path $backupFile -Encoding UTF8
        Write-Host "    Backed up existing" -ForegroundColor DarkGray

        $body = @{ disabled = 0; script = $newScript } | ConvertTo-Json -Depth 10 -Compress
        try {
            Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script/$(Enc $scriptName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
            Write-Host "    Updated successfully" -ForegroundColor Green
            $success++
        } catch {
            Write-Host "    ERROR updating: $_" -ForegroundColor Red
            $failed++
        }
    } else {
        Write-Host "    Script not found on server, creating new..." -ForegroundColor Yellow
        $body = @{
            doctype = "Server Script"
            name = $scriptName
            script_type = "DocType Event"
            reference_doctype = $s.DocType
            doctype_event = $s.Event
            disabled = 0
            script = $newScript
        } | ConvertTo-Json -Depth 10 -Compress
        try {
            Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
            Write-Host "    Created successfully" -ForegroundColor Green
            $success++
        } catch {
            Write-Host "    ERROR creating: $_" -ForegroundColor Red
            $failed++
        }
    }
}

# ---- Disable obsolete Server Scripts ----
Write-Host ""
Write-Host "--- DISABLING OBSOLETE SERVER SCRIPTS ---" -ForegroundColor Magenta
foreach ($scriptName in $DisableServerScripts) {
    Write-Host "  [$scriptName]" -ForegroundColor Cyan
    try {
        $body = @{ disabled = 1 } | ConvertTo-Json -Depth 10 -Compress
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script/$(Enc $scriptName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
        Write-Host "    Disabled successfully" -ForegroundColor Green
        $success++
    } catch {
        Write-Host "    WARN: Could not disable (may not exist): $_" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=== Done: $success updated, $failed failed ===" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
Write-Host "Backups in: $BackupDir" -ForegroundColor DarkGray
Write-Host "Hard-refresh the browser to pick up the client script changes." -ForegroundColor Yellow
Write-Host "Server script changes take effect immediately (no restart needed)." -ForegroundColor Yellow
