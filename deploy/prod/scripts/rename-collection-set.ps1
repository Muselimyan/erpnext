#Requires -Version 5.1
<#
.SYNOPSIS
    Renames "Surgery Set Type Item" -> "Collection Set Item"
    and   "Surgery Set Type"        -> "Collection Set"
    in production, then updates the server script and custom field references.

.PARAMETER Mode
    Check  - report current state without making changes (default)
    Deploy - execute the renames (idempotent: skips steps already done)
#>
param(
    [ValidateSet("Check","Deploy")]
    [string]$Mode = "Check"
)

Set-StrictMode -Off

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config     = Get-Content $ConfigPath -Raw
$BaseUrl    = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey     = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec     = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers    = @{
    Authorization  = "token $($ApiKey):$($ApiSec)"
    "Content-Type" = "application/json"
}

function Enc ([string]$s) { [uri]::EscapeDataString($s) }

function Invoke-ErpRequest {
    param([string]$Method, [string]$Path, $Body = $null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) {
        return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -ErrorAction Stop
    }
    $Json      = $Body | ConvertTo-Json -Depth 30
    $JsonBytes = [System.Text.Encoding]::UTF8.GetBytes($Json)
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body $JsonBytes -ErrorAction Stop
}

function Get-ErpDoc {
    param([string]$DocType, [string]$Name)
    try   { return (Invoke-ErpRequest -Method Get -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)").data }
    catch { return $null }
}

function Rename-ErpDoc {
    param([string]$DocType, [string]$OldName, [string]$NewName)
    try {
        $Result = Invoke-ErpRequest -Method Post `
            -Path "/api/method/frappe.client.rename_doc" `
            -Body @{ doctype = $DocType; old_name = $OldName; new_name = $NewName; merge = $false }
        return [pscustomobject]@{ action = "renamed"; from = $OldName; to = $NewName; result = $Result }
    } catch {
        return [pscustomobject]@{ action = "error"; from = $OldName; to = $NewName; error = $_.Exception.Message }
    }
}

Write-Host ""
Write-Host "=== Collection Set Rename - Mode: $Mode ===" -ForegroundColor Cyan

$ChildOld  = "Surgery Set Type Item"
$ChildNew  = "Collection Set Item"
$ParentOld = "Surgery Set Type"
$ParentNew = "Collection Set"
$ScriptOld = "Surgery-Set-Type-validate-readiness"
$ScriptNew = "Collection-Set-validate-readiness"

$ChildExists     = $null -ne (Get-ErpDoc "DocType" $ChildOld)
$ChildNewExists  = $null -ne (Get-ErpDoc "DocType" $ChildNew)
$ParentExists    = $null -ne (Get-ErpDoc "DocType" $ParentOld)
$ParentNewExists = $null -ne (Get-ErpDoc "DocType" $ParentNew)
$ScriptExists    = $null -ne (Get-ErpDoc "Server Script" $ScriptOld)
$ScriptNewExists = $null -ne (Get-ErpDoc "Server Script" $ScriptNew)

Write-Host ""
Write-Host "Current state:"
Write-Host "  DocType '$ChildOld' exists: $ChildExists"
Write-Host "  DocType '$ChildNew' exists: $ChildNewExists"
Write-Host "  DocType '$ParentOld' exists: $ParentExists"
Write-Host "  DocType '$ParentNew' exists: $ParentNewExists"
Write-Host "  Server Script '$ScriptOld' exists: $ScriptExists"
Write-Host "  Server Script '$ScriptNew' exists: $ScriptNewExists"

if ($Mode -eq "Check") {
    Write-Host ""
    Write-Host "Run with -Mode Deploy to apply changes." -ForegroundColor Yellow
    exit 0
}

$Results = [System.Collections.ArrayList]::new()

# Step 1 - Rename child table
Write-Host ""
Write-Host "[1/4] Renaming child table DocType..." -ForegroundColor Yellow
if ($ChildNewExists) {
    Write-Host "  '$ChildNew' already exists - skipping."
    $Results.Add([pscustomobject]@{ step = 1; action = "skipped"; name = $ChildNew }) | Out-Null
} elseif (-not $ChildExists) {
    Write-Host "  WARNING: '$ChildOld' not found - cannot rename." -ForegroundColor Red
    $Results.Add([pscustomobject]@{ step = 1; action = "missing"; name = $ChildOld }) | Out-Null
} else {
    $R = Rename-ErpDoc "DocType" $ChildOld $ChildNew
    Write-Host "  Result: $($R.action)"
    $Results.Add($R) | Out-Null
    Start-Sleep -Seconds 2
}

# Step 2 - Rename parent DocType
Write-Host ""
Write-Host "[2/4] Renaming parent DocType..." -ForegroundColor Yellow
if ($ParentNewExists) {
    Write-Host "  '$ParentNew' already exists - skipping."
    $Results.Add([pscustomobject]@{ step = 2; action = "skipped"; name = $ParentNew }) | Out-Null
} elseif (-not $ParentExists) {
    Write-Host "  WARNING: '$ParentOld' not found - cannot rename." -ForegroundColor Red
    $Results.Add([pscustomobject]@{ step = 2; action = "missing"; name = $ParentOld }) | Out-Null
} else {
    $R = Rename-ErpDoc "DocType" $ParentOld $ParentNew
    Write-Host "  Result: $($R.action)"
    $Results.Add($R) | Out-Null
    Start-Sleep -Seconds 3
}

# Step 3 - Update server script
Write-Host ""
Write-Host "[3/4] Updating server script..." -ForegroundColor Yellow

if ($ScriptNewExists) { $ScriptNameNow = $ScriptNew }
elseif ($ScriptExists) { $ScriptNameNow = $ScriptOld }
else { $ScriptNameNow = $null }

if ($null -eq $ScriptNameNow) {
    Write-Host "  WARNING: Server script not found under either name." -ForegroundColor Red
    $Results.Add([pscustomobject]@{ step = 3; action = "missing" }) | Out-Null
} else {
    $ScriptDoc     = Get-ErpDoc "Server Script" $ScriptNameNow
    $OldText       = if ($null -ne $ScriptDoc) { $ScriptDoc.script } else { "" }
    $NewText       = $OldText.Replace("Surgery Set Type", "Collection Set")
    $UpdateBody    = [ordered]@{ reference_doctype = $ParentNew; script = $NewText }
    try {
        Invoke-ErpRequest -Method Put -Path "/api/resource/Server Script/$(Enc $ScriptNameNow)" -Body $UpdateBody | Out-Null
        Write-Host "  Updated '$ScriptNameNow' content and reference_doctype."
        $Results.Add([pscustomobject]@{ step = 3; action = "updated"; name = $ScriptNameNow }) | Out-Null
    } catch {
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
        $Results.Add([pscustomobject]@{ step = 3; action = "error"; error = $_.Exception.Message }) | Out-Null
    }
    if ($ScriptNameNow -eq $ScriptOld -and (-not $ScriptNewExists)) {
        $R = Rename-ErpDoc "Server Script" $ScriptOld $ScriptNew
        Write-Host "  Renamed server script: $($R.action)"
        $Results.Add($R) | Out-Null
    }
}

# Step 4 - Patch Dispatch Case custom field options
Write-Host ""
Write-Host "[4/4] Patching Dispatch Case custom field options..." -ForegroundColor Yellow
$CfFilter  = Enc '[["dt","=","Dispatch Case"],["fieldname","=","surgery_set_type"]]'
$FieldList = $null
try {
    $FieldList = (Invoke-ErpRequest -Method Get -Path "/api/resource/Custom Field?filters=$CfFilter&limit=5").data
} catch {
    Write-Host "  ERROR fetching field: $($_.Exception.Message)" -ForegroundColor Red
    $Results.Add([pscustomobject]@{ step = 4; action = "error"; error = $_.Exception.Message }) | Out-Null
}

if ($null -ne $FieldList -and $FieldList.Count -gt 0) {
    $FieldName = $FieldList[0].name
    $FieldDoc  = Get-ErpDoc "Custom Field" $FieldName
    if ($FieldDoc.options -eq $ParentOld) {
        try {
            Invoke-ErpRequest -Method Put -Path "/api/resource/Custom Field/$(Enc $FieldName)" -Body @{ options = $ParentNew } | Out-Null
            Write-Host "  Updated '$FieldName' options -> '$ParentNew'."
            $Results.Add([pscustomobject]@{ step = 4; action = "updated"; name = $FieldName }) | Out-Null
        } catch {
            Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
            $Results.Add([pscustomobject]@{ step = 4; action = "error"; error = $_.Exception.Message }) | Out-Null
        }
    } else {
        Write-Host "  Already '$($FieldDoc.options)' - no change needed."
        $Results.Add([pscustomobject]@{ step = 4; action = "skipped"; name = $FieldName }) | Out-Null
    }
} elseif ($null -ne $FieldList) {
    Write-Host "  Field 'surgery_set_type' on 'Dispatch Case' not found - check manually." -ForegroundColor Yellow
    $Results.Add([pscustomobject]@{ step = 4; action = "not-found" }) | Out-Null
}

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
$Results | Format-Table -AutoSize
Write-Host ""
Write-Host "Done. Run export.ps1 to sync schema JSON." -ForegroundColor Green
