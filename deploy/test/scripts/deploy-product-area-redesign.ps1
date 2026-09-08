#Requires -Version 5.1
# ============================================================================
# Deploy — Product Area Redesign
# Target: TEST only (test.erpnext.am)
#
# 1. Delete Column Break + Warning field (full-width product table)
# 2. Update 3 client scripts (PWA, TFV, Account Details UI Cleanup)
# 3. Fix stale field_order Property Setter (remove ghost/deleted fields)
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

function Delete-ErpDoc([string]$DocType, [string]$Name) {
    return Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)" -Headers $Headers -Method Delete -TimeoutSec 30
}

function Read-WorkScript([string]$Path) {
    $Content = Get-Content $Path -Raw -Encoding UTF8
    if ($Content -match '(?s)^.*?//\s*---\s*\r?\n') {
        $Content = $Content.Substring($Matches[0].Length)
    }
    return $Content.TrimEnd()
}

$WorkDir = Join-Path (Split-Path $PSScriptRoot) "work"

Write-Host "`n=== Product Area Redesign ===" -ForegroundColor Cyan
Write-Host "Target: $BaseUrl" -ForegroundColor Yellow
Write-Host "Mode:   $Mode`n" -ForegroundColor Yellow

# ============================================================================
# Step 1: Delete Column Break + Warning field
# ============================================================================
Write-Host "[1] Delete Column Break + Warning field" -ForegroundColor Magenta

$FieldsToDelete = @(
    "Task-custom_product_work_column",
    "Task-custom_task_product_warning"
)

foreach ($cfName in $FieldsToDelete) {
    $existing = Get-ErpDoc "Custom Field" $cfName
    if ($Mode -eq "Check") {
        if ($existing) {
            Write-Host "  $cfName : EXISTS (will delete)" -ForegroundColor Yellow
        } else {
            Write-Host "  $cfName : already gone" -ForegroundColor DarkGray
        }
    } else {
        if ($existing) {
            Delete-ErpDoc "Custom Field" $cfName | Out-Null
            Write-Host "  $cfName : DELETED" -ForegroundColor Green
        } else {
            Write-Host "  $cfName : already gone" -ForegroundColor DarkGray
        }
    }
}

# ============================================================================
# Step 2: Update 3 client scripts
# ============================================================================
Write-Host "`n[2] Update client scripts (3)" -ForegroundColor Magenta

$ClientScripts = @(
    @{ Name = "Task-Product Work Area";       File = "client\Task-Product Work Area.js" },
    @{ Name = "Task-Field-Visibility";        File = "client\Task-Field-Visibility.js" },
    @{ Name = "Task-Account Details UI Cleanup"; File = "client\Task-Account Details UI Cleanup.js" }
)

foreach ($s in $ClientScripts) {
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

# ============================================================================
# Step 3: Fix stale field_order Property Setter
# ============================================================================
Write-Host "`n[3] Fix stale field_order Property Setter" -ForegroundColor Magenta

$psName = "Task-main-field_order"
$existing = Get-ErpDoc "Property Setter" $psName
if ($existing) {
    $currentOrder = $existing.value | ConvertFrom-Json
    $staleFields = @(
        "custom_barcode_section",
        "custom_product_work_column",
        "custom_task_product_warning",
        "custom_task_add_item_code",
        "custom_task_add_qty",
        "custom_task_add_batch_no",
        "custom_task_add_unit_price"
    )
    $cleanOrder = $currentOrder | Where-Object { $staleFields -notcontains $_ }
    $removed = $currentOrder.Count - $cleanOrder.Count

    if ($Mode -eq "Check") {
        if ($removed -gt 0) {
            Write-Host "  WOULD REMOVE $removed stale entries: $($staleFields -join ', ')" -ForegroundColor Yellow
            Write-Host "  Field count: $($currentOrder.Count) -> $($cleanOrder.Count)" -ForegroundColor Yellow
        } else {
            Write-Host "  No stale entries found ($($currentOrder.Count) fields)" -ForegroundColor DarkGray
        }
    } else {
        if ($removed -gt 0) {
            $newValue = $cleanOrder | ConvertTo-Json -Compress
            Put-ErpDoc "Property Setter" $psName @{ value = $newValue } | Out-Null
            Write-Host "  REMOVED $removed stale entries ($($currentOrder.Count) -> $($cleanOrder.Count) fields)" -ForegroundColor Green
        } else {
            Write-Host "  No stale entries found" -ForegroundColor DarkGray
        }
    }
} else {
    Write-Host "  Property Setter $psName not found" -ForegroundColor Red
}

# --- Clear cache ---
if ($Mode -eq "Deploy") {
    Write-Host "`n[Cache] Clearing..." -ForegroundColor Magenta
    $sshKey = "$env:USERPROFILE\.ssh\vps_erpnext2"
    ssh -i $sshKey root@161.97.83.156 "docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    Write-Host "  Cache cleared" -ForegroundColor Green
}

Write-Host "`n=== Done ===" -ForegroundColor Cyan
