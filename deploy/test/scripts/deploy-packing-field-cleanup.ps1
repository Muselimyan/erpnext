#Requires -Version 5.1
# ============================================================================
# Deploy — Packing Field Cleanup
# Target: TEST only (test.erpnext.am)
#
# 1. Delete 5 Custom Fields on Dispatch Case Item (derived + dead)
# 2. Delete 7 Custom Fields on Dispatch Case (scan UI + problem alerts)
# 3. Delete 2 Property Setters
# 4. Fix insert_after chain (custom_scanned_qty)
# 5. Delete 3 scripts (server + client)
# 6. Update 6 server scripts
# 7. Update 3 client scripts
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

Write-Host "`n=== Packing Field Cleanup ===" -ForegroundColor Cyan
Write-Host "Target: $BaseUrl" -ForegroundColor Yellow
Write-Host "Mode:   $Mode`n" -ForegroundColor Yellow

# ============================================================================
# Step 1: Delete 5 Custom Fields on Dispatch Case Item
# ============================================================================
Write-Host "[1] Delete Dispatch Case Item Custom Fields (5)" -ForegroundColor Magenta

$ItemFields = @(
    "Dispatch Case Item-custom_packing_status",
    "Dispatch Case Item-custom_remaining_qty",
    "Dispatch Case Item-custom_scan_note",
    "Dispatch Case Item-custom_problem_reason",
    "Dispatch Case Item-custom_problem_alert_sent"
)

foreach ($cfName in $ItemFields) {
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
# Step 2: Delete 7 Custom Fields on Dispatch Case
# ============================================================================
Write-Host "`n[2] Delete Dispatch Case Custom Fields (7)" -ForegroundColor Magenta

$CaseFields = @(
    "Dispatch Case-custom_packing_scan_barcode",
    "Dispatch Case-custom_packing_scan_qty",
    "Dispatch Case-custom_packing_scan_result",
    "Dispatch Case-custom_packing_last_warning",
    "Dispatch Case-custom_packing_problem_status",
    "Dispatch Case-custom_packing_problem_summary",
    "Dispatch Case-custom_problem_alert_sent"
)

foreach ($cfName in $CaseFields) {
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
# Step 3: Delete 2 Property Setters
# ============================================================================
Write-Host "`n[3] Delete Property Setters (2)" -ForegroundColor Magenta

$PropertySetters = @(
    "Dispatch Case Item-custom_packing_status-allow_on_submit",
    "Dispatch Case Item-custom_remaining_qty-allow_on_submit"
)

foreach ($psName in $PropertySetters) {
    $existing = Get-ErpDoc "Property Setter" $psName
    if ($Mode -eq "Check") {
        if ($existing) {
            Write-Host "  $psName : EXISTS (will delete)" -ForegroundColor Yellow
        } else {
            Write-Host "  $psName : already gone" -ForegroundColor DarkGray
        }
    } else {
        if ($existing) {
            Delete-ErpDoc "Property Setter" $psName | Out-Null
            Write-Host "  $psName : DELETED" -ForegroundColor Green
        } else {
            Write-Host "  $psName : already gone" -ForegroundColor DarkGray
        }
    }
}

# ============================================================================
# Step 4: Fix insert_after chain (custom_scanned_qty)
# ============================================================================
Write-Host "`n[4] Fix custom_scanned_qty insert_after" -ForegroundColor Magenta

$scannedField = Get-ErpDoc "Custom Field" "Dispatch Case Item-custom_scanned_qty"
if ($scannedField) {
    $currentInsert = $scannedField.insert_after
    if ($Mode -eq "Check") {
        if ($currentInsert -eq "dispatched_qty") {
            Write-Host "  insert_after already correct: dispatched_qty" -ForegroundColor DarkGray
        } else {
            Write-Host "  insert_after: $currentInsert -> dispatched_qty (will update)" -ForegroundColor Yellow
        }
    } else {
        if ($currentInsert -ne "dispatched_qty") {
            Put-ErpDoc "Custom Field" "Dispatch Case Item-custom_scanned_qty" @{
                insert_after = "dispatched_qty"
            } | Out-Null
            Write-Host "  insert_after: $currentInsert -> dispatched_qty UPDATED" -ForegroundColor Green
        } else {
            Write-Host "  insert_after already correct" -ForegroundColor DarkGray
        }
    }
} else {
    Write-Host "  ERROR: custom_scanned_qty field not found!" -ForegroundColor Red
}

# ============================================================================
# Step 5: Delete 3 scripts
# ============================================================================
Write-Host "`n[5] Delete scripts (3)" -ForegroundColor Magenta

$ScriptsToDelete = @(
    @{ DocType = "Server Script"; Name = "Dispatch Case-packing-problem-alerts" },
    @{ DocType = "Client Script"; Name = "Dispatch Case-Packing Problem Alerts" },
    @{ DocType = "Client Script"; Name = "Dispatch Case-Packing Scan" }
)

foreach ($s in $ScriptsToDelete) {
    $existing = Get-ErpDoc $s.DocType $s.Name
    if ($Mode -eq "Check") {
        if ($existing) {
            Write-Host "  [$($s.DocType)] $($s.Name) : EXISTS (will delete)" -ForegroundColor Yellow
        } else {
            Write-Host "  [$($s.DocType)] $($s.Name) : already gone" -ForegroundColor DarkGray
        }
    } else {
        if ($existing) {
            Delete-ErpDoc $s.DocType $s.Name | Out-Null
            Write-Host "  [$($s.DocType)] $($s.Name) : DELETED" -ForegroundColor Green
        } else {
            Write-Host "  [$($s.DocType)] $($s.Name) : already gone" -ForegroundColor DarkGray
        }
    }
}

# ============================================================================
# Step 6: Update 6 server scripts
# ============================================================================
Write-Host "`n[6] Update server scripts (6)" -ForegroundColor Magenta

$ServerScripts = @(
    @{ Name = "task_add_dispatch_product";       File = "server\task_add_dispatch_product.py" },
    @{ Name = "task_update_dispatch_product";    File = "server\task_update_dispatch_product.py" },
    @{ Name = "task_mark_item_packed";           File = "server\task_mark_item_packed.py" },
    @{ Name = "task_mark_items_packed_batch";    File = "server\task_mark_items_packed_batch.py" },
    @{ Name = "dispatch_case_packing_scan";      File = "server\dispatch_case_packing_scan.py" },
    @{ Name = "Task-before-save-dispatch-gates"; File = "server\Task-before-save-dispatch-gates.py" }
)

foreach ($s in $ServerScripts) {
    $filePath = Join-Path $WorkDir $s.File
    if (-not (Test-Path $filePath)) {
        Write-Host "  ERROR: File not found: $filePath" -ForegroundColor Red
        continue
    }
    $newScript = Read-ServerScript $filePath
    $existing = Get-ErpDoc "Server Script" $s.Name

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
        Put-ErpDoc "Server Script" $s.Name @{
            script = $newScript
        } | Out-Null
        Write-Host "  [$($s.Name)] UPDATED ($($newScript.Length) chars)" -ForegroundColor Green
    }
}

# ============================================================================
# Step 7: Update 3 client scripts
# ============================================================================
Write-Host "`n[7] Update client scripts (3)" -ForegroundColor Magenta

$ClientScripts = @(
    @{ Name = "Task-Product Work Area";                    File = "client\Task-Product Work Area.js" },
    @{ Name = "Dispatch Case-Simplify for Order Creation"; File = "client\Dispatch Case-Simplify for Order Creation.js" },
    @{ Name = "Dispatch Case-Form";                        File = "client\Dispatch Case-Form.js" }
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

# --- Clear cache ---
if ($Mode -eq "Deploy") {
    Write-Host "`n[Cache] Clearing..." -ForegroundColor Magenta
    $sshKey = "$env:USERPROFILE\.ssh\vps_erpnext2"
    ssh -i $sshKey root@161.97.83.156 "docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    Write-Host "  Cache cleared" -ForegroundColor Green
}

Write-Host "`n=== Done ===" -ForegroundColor Cyan
