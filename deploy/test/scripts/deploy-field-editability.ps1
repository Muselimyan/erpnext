#Requires -Version 5.1
# ============================================================================
# Deploy — Task Field Editability (TFE)
# Target: TEST only (test.erpnext.am)
#
# 1. CREATE/UPDATE client script: Task-Field-Editability.js
# 2. UPDATE client scripts: Task-Product Work Area.js, Task-Field-Visibility.js
# 3. DISABLE client scripts: Task-Lock Unaccepted.js, Task-Lock Completed.js
# 4. UPDATE 8 server scripts with acceptance checks:
#    task_add_dispatch_product, task_update_dispatch_product,
#    task_remove_dispatch_product, dispatch_case_packing_scan,
#    task_mark_item_packed, task_mark_items_packed_batch,
#    task_update_return_item_quantities, task_apply_template
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

function Read-WorkScript([string]$Path) {
    $Content = Get-Content $Path -Raw -Encoding UTF8
    if ($Content -match '(?s)^.*?//\s*---\s*\r?\n') {
        $Content = $Content.Substring($Matches[0].Length)
    }
    return $Content.TrimEnd()
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

$WorkDir = Join-Path (Split-Path $PSScriptRoot) "work"

Write-Host "`n=== Task Field Editability (TFE) ===" -ForegroundColor Cyan
Write-Host "Target: $BaseUrl" -ForegroundColor Yellow
Write-Host "Mode:   $Mode`n" -ForegroundColor Yellow

# ============================================================================
# Step 1: CREATE/UPDATE Task-Field-Editability.js
# ============================================================================
Write-Host "[1] Task-Field-Editability (new script)" -ForegroundColor Magenta

$tfePath = Join-Path $WorkDir "client\Task-Field-Editability.js"
$tfeScript = Read-WorkScript $tfePath
$existingTFE = Get-ErpDoc "Client Script" "Task-Field-Editability"

if ($Mode -eq "Check") {
    if ($existingTFE) {
        $currentLen = ([string]$existingTFE.script).Length
        $same = $currentLen -eq $tfeScript.Length -and $existingTFE.script -eq $tfeScript
        if ($same) {
            Write-Host "  Task-Field-Editability: UNCHANGED ($currentLen chars)" -ForegroundColor DarkGray
        } else {
            Write-Host "  Task-Field-Editability: WOULD UPDATE ($currentLen -> $($tfeScript.Length) chars)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  Task-Field-Editability: WOULD CREATE ($($tfeScript.Length) chars)" -ForegroundColor Yellow
    }
} else {
    if ($existingTFE) {
        Put-ErpDoc "Client Script" "Task-Field-Editability" @{
            script  = $tfeScript
            enabled = 1
        } | Out-Null
        Write-Host "  Task-Field-Editability: UPDATED ($($tfeScript.Length) chars)" -ForegroundColor Green
    } else {
        Post-ErpDoc "Client Script" @{
            name    = "Task-Field-Editability"
            dt      = "Task"
            view    = "Form"
            script  = $tfeScript
            enabled = 1
        } | Out-Null
        Write-Host "  Task-Field-Editability: CREATED ($($tfeScript.Length) chars)" -ForegroundColor Green
    }
}

# ============================================================================
# Step 2: UPDATE Task-Product Work Area + Task-Field-Visibility
# ============================================================================
Write-Host "`n[2] Update client scripts" -ForegroundColor Magenta

$UpdateScripts = @(
    @{ Name = "Task-Product Work Area"; File = "client\Task-Product Work Area.js" },
    @{ Name = "Task-Field-Visibility"; File = "client\Task-Field-Visibility.js" }
)

foreach ($s in $UpdateScripts) {
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
# Step 3: DISABLE Task-Lock Unaccepted + Task-Lock Completed
# ============================================================================
Write-Host "`n[3] Disable absorbed lock scripts" -ForegroundColor Magenta

$DisableScripts = @("Task-Lock Unaccepted", "Task-Lock Completed")

foreach ($name in $DisableScripts) {
    $existing = Get-ErpDoc "Client Script" $name

    if ($Mode -eq "Check") {
        if ($existing) {
            $isEnabled = $existing.enabled -eq 1
            if ($isEnabled) {
                Write-Host "  [$name] ENABLED (will disable)" -ForegroundColor Yellow
            } else {
                Write-Host "  [$name] already disabled" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "  [$name] NOT FOUND" -ForegroundColor DarkGray
        }
    } else {
        if ($existing) {
            Put-ErpDoc "Client Script" $name @{ enabled = 0 } | Out-Null
            Write-Host "  [$name] DISABLED" -ForegroundColor Green
        } else {
            Write-Host "  [$name] NOT FOUND -- SKIP" -ForegroundColor DarkGray
        }
    }
}

# ============================================================================
# Step 4: UPDATE 8 server scripts (acceptance checks)
# ============================================================================
Write-Host "`n[4] Server Scripts (acceptance checks)" -ForegroundColor Magenta

$ServerScripts = @(
    @{ name = "task_add_dispatch_product";            file = "server\task_add_dispatch_product.py" },
    @{ name = "task_update_dispatch_product";          file = "server\task_update_dispatch_product.py" },
    @{ name = "task_remove_dispatch_product";          file = "server\task_remove_dispatch_product.py" },
    @{ name = "dispatch_case_packing_scan";            file = "server\dispatch_case_packing_scan.py" },
    @{ name = "task_mark_item_packed";                 file = "server\task_mark_item_packed.py" },
    @{ name = "task_mark_items_packed_batch";           file = "server\task_mark_items_packed_batch.py" },
    @{ name = "task_update_return_item_quantities";     file = "server\task_update_return_item_quantities.py" },
    @{ name = "task_apply_template";                   file = "server\task_apply_template.py" }
)

foreach ($ss in $ServerScripts) {
    $scriptPath = Join-Path $WorkDir $ss.file
    if (-not (Test-Path $scriptPath)) {
        Write-Host "  ERROR: $scriptPath not found" -ForegroundColor Red
        continue
    }
    $scriptBody = Read-ServerScript $scriptPath
    $existing = Get-ErpDoc "Server Script" $ss.name

    if ($Mode -eq "Check") {
        if ($existing) {
            $currentLen = ([string]$existing.script).Length
            $same = $currentLen -eq $scriptBody.Length -and $existing.script -eq $scriptBody
            if ($same) {
                Write-Host "  $($ss.name): UNCHANGED ($currentLen chars)" -ForegroundColor DarkGray
            } else {
                Write-Host "  $($ss.name): WOULD UPDATE ($currentLen -> $($scriptBody.Length) chars)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  $($ss.name): NOT FOUND on server" -ForegroundColor Red
        }
    } else {
        if (-not $existing) {
            Write-Host "  $($ss.name): NOT FOUND on server -- SKIP" -ForegroundColor Red
            continue
        }
        Put-ErpDoc "Server Script" $ss.name @{ script = $scriptBody; disabled = 0 } | Out-Null
        Write-Host "  $($ss.name): UPDATED" -ForegroundColor Green
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
