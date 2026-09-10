#Requires -Version 5.1
# ============================================================================
# Deploy — Phase 2 DC Form Cleanup
# Target: TEST only (test.erpnext.am)
#
# 1. Add allow_on_submit property setter for discount_pct
# 2. Set track_changes = 1 on Dispatch Case DocType
# 3. Delete dead custom field: allow_items_edit (was used by removed lock logic)
# 4. Update Dispatch Case-Form.js (simplified: removed allow_items_edit,
#    hardcoded approvers, custom lock/unlock)
# 5. Disable Dispatch Case-Lock Submitted.js (conflicts with allow_on_submit)
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

function New-ErpDoc([string]$DocType, $Body) {
    $Json = $Body | ConvertTo-Json -Depth 20 -Compress
    return Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 60
}

function Read-WorkScript([string]$Path) {
    $Content = Get-Content $Path -Raw -Encoding UTF8
    if ($Content -match '(?s)^.*?//\s*---\s*\r?\n') {
        $Content = $Content.Substring($Matches[0].Length)
    }
    return $Content.TrimEnd()
}

$WorkDir = Join-Path (Split-Path $PSScriptRoot) "work"

Write-Host "`n=== Phase 2: DC Form Cleanup ===" -ForegroundColor Cyan
Write-Host "Target: $BaseUrl" -ForegroundColor Yellow
Write-Host "Mode:   $Mode`n" -ForegroundColor Yellow

# ============================================================================
# Step 1: Add allow_on_submit for discount_pct
# ============================================================================
Write-Host "[1] Add allow_on_submit for Dispatch Case Item-discount_pct" -ForegroundColor Magenta

$psName = "Dispatch Case Item-discount_pct-allow_on_submit"
$existing = Get-ErpDoc "Property Setter" $psName

if ($Mode -eq "Check") {
    if ($existing) {
        Write-Host "  $psName : already EXISTS (value=$($existing.value))" -ForegroundColor DarkGray
    } else {
        Write-Host "  $psName : MISSING (will create)" -ForegroundColor Yellow
    }
} else {
    if ($existing) {
        Write-Host "  $psName : already exists" -ForegroundColor DarkGray
    } else {
        New-ErpDoc "Property Setter" @{
            name            = $psName
            doctype_or_field = "DocField"
            doc_type        = "Dispatch Case Item"
            field_name      = "discount_pct"
            property        = "allow_on_submit"
            value           = "1"
            property_type   = "Check"
        } | Out-Null
        Write-Host "  $psName : CREATED" -ForegroundColor Green
    }
}

# ============================================================================
# Step 2: Set track_changes = 1 on Dispatch Case
# ============================================================================
Write-Host "`n[2] Set track_changes = 1 on Dispatch Case DocType" -ForegroundColor Magenta

$dcDoc = Get-ErpDoc "DocType" "Dispatch Case"

if ($Mode -eq "Check") {
    if ($dcDoc) {
        $current = $dcDoc.track_changes
        if ($current -eq 1) {
            Write-Host "  track_changes already 1" -ForegroundColor DarkGray
        } else {
            Write-Host "  track_changes is $current (will set to 1)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  Dispatch Case DocType NOT FOUND" -ForegroundColor Red
    }
} else {
    if ($dcDoc -and $dcDoc.track_changes -ne 1) {
        Put-ErpDoc "DocType" "Dispatch Case" @{ track_changes = 1 } | Out-Null
        Write-Host "  track_changes set to 1" -ForegroundColor Green
    } elseif ($dcDoc) {
        Write-Host "  track_changes already 1" -ForegroundColor DarkGray
    } else {
        Write-Host "  Dispatch Case DocType NOT FOUND" -ForegroundColor Red
    }
}

# ============================================================================
# Step 3: Delete dead custom field: allow_items_edit
# ============================================================================
Write-Host "`n[3] Delete dead custom field: allow_items_edit" -ForegroundColor Magenta

$cfName = "Dispatch Case-allow_items_edit"
$existing = Get-ErpDoc "Custom Field" $cfName

if ($Mode -eq "Check") {
    if ($existing) {
        Write-Host "  $cfName : EXISTS (will delete)" -ForegroundColor Yellow
    } else {
        Write-Host "  $cfName : already gone" -ForegroundColor DarkGray
    }
} else {
    if ($existing) {
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc 'Custom Field')/$(Enc $cfName)" -Headers $Headers -Method Delete -TimeoutSec 30 | Out-Null
        Write-Host "  $cfName : DELETED" -ForegroundColor Green
    } else {
        Write-Host "  $cfName : already gone" -ForegroundColor DarkGray
    }
}

# ============================================================================
# Step 4: Update Dispatch Case-Form.js (simplified)
# ============================================================================
Write-Host "`n[4] Update Dispatch Case-Form.js (simplified)" -ForegroundColor Magenta

$formFile = Join-Path $WorkDir "client\Dispatch Case-Form.js"
if (-not (Test-Path $formFile)) {
    Write-Host "  ERROR: File not found: $formFile" -ForegroundColor Red
} else {
    $newScript = Read-WorkScript $formFile
    $existing = Get-ErpDoc "Client Script" "Dispatch Case-Form"

    if ($Mode -eq "Check") {
        if ($existing) {
            $currentLen = ([string]$existing.script).Length
            $same = $currentLen -eq $newScript.Length -and $existing.script -eq $newScript
            if ($same) {
                Write-Host "  [Dispatch Case-Form] UNCHANGED ($currentLen chars)" -ForegroundColor DarkGray
            } else {
                Write-Host "  [Dispatch Case-Form] WOULD UPDATE ($currentLen -> $($newScript.Length) chars)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  [Dispatch Case-Form] NOT FOUND on server" -ForegroundColor Red
        }
    } else {
        if (-not $existing) {
            Write-Host "  [Dispatch Case-Form] NOT FOUND on server -- SKIP" -ForegroundColor Red
        } else {
            Put-ErpDoc "Client Script" "Dispatch Case-Form" @{
                script  = $newScript
                enabled = 1
            } | Out-Null
            Write-Host "  [Dispatch Case-Form] UPDATED ($($newScript.Length) chars)" -ForegroundColor Green
        }
    }
}

# ============================================================================
# Step 5: Disable Dispatch Case-Lock Submitted.js
# ============================================================================
Write-Host "`n[5] Disable Dispatch Case-Lock Submitted.js" -ForegroundColor Magenta

$lockDoc = Get-ErpDoc "Client Script" "Dispatch Case-Lock Submitted"

if ($Mode -eq "Check") {
    if ($lockDoc) {
        if ($lockDoc.enabled -eq 0) {
            Write-Host "  [Dispatch Case-Lock Submitted] already disabled" -ForegroundColor DarkGray
        } else {
            Write-Host "  [Dispatch Case-Lock Submitted] ENABLED (will disable)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [Dispatch Case-Lock Submitted] NOT FOUND" -ForegroundColor Red
    }
} else {
    if ($lockDoc -and $lockDoc.enabled -ne 0) {
        Put-ErpDoc "Client Script" "Dispatch Case-Lock Submitted" @{
            enabled = 0
        } | Out-Null
        Write-Host "  [Dispatch Case-Lock Submitted] DISABLED" -ForegroundColor Green
    } elseif ($lockDoc) {
        Write-Host "  [Dispatch Case-Lock Submitted] already disabled" -ForegroundColor DarkGray
    } else {
        Write-Host "  [Dispatch Case-Lock Submitted] NOT FOUND" -ForegroundColor Red
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
