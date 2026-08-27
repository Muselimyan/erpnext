Set-StrictMode -Off

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config     = Get-Content $ConfigPath -Raw
$BaseUrl    = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey     = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec     = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers    = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json"; "User-Agent" = "Mozilla/5.0" }

function Enc ([string]$s) { [uri]::EscapeDataString($s) }

function Invoke-ErpRequest { 
    param([string]$Method, [string]$Path, $Body=$null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { 
        return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 120 
    }
    $Json = $Body | ConvertTo-Json -Depth 40 -Compress
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 120
}

function Add-Permission {
    param(
        [string]$DocType,
        [string]$Role,
        [bool]$Read = $false,
        [bool]$Write = $false,
        [bool]$Create = $false,
        [bool]$Delete = $false,
        [bool]$Submit = $false,
        [bool]$Cancel = $false
    )
    
    Write-Host "Setting permissions for $Role on $DocType..." -ForegroundColor Yellow
    
    try {
        # Get the DocType
        $uri = "$BaseUrl/api/resource/DocType/$(Enc $DocType)"
        $doctype = Invoke-RestMethod -Uri $uri -Headers $Headers -Method Get -TimeoutSec 30
        
        # Check if permission already exists
        $existingPerm = $doctype.data.permissions | Where-Object { $_.role -eq $Role -and $_.permlevel -eq 0 } | Select-Object -First 1
        
        if ($existingPerm) {
            # Update existing permission
            $existingPerm.read = if ($Read) { 1 } else { 0 }
            $existingPerm.write = if ($Write) { 1 } else { 0 }
            $existingPerm.create = if ($Create) { 1 } else { 0 }
            $existingPerm.delete = if ($Delete) { 1 } else { 0 }
            $existingPerm.submit = if ($Submit) { 1 } else { 0 }
            $existingPerm.cancel = if ($Cancel) { 1 } else { 0 }
        } else {
            # Add new permission
            $newPerm = @{
                role = $Role
                permlevel = 0
                read = if ($Read) { 1 } else { 0 }
                write = if ($Write) { 1 } else { 0 }
                create = if ($Create) { 1 } else { 0 }
                delete = if ($Delete) { 1 } else { 0 }
                submit = if ($Submit) { 1 } else { 0 }
                cancel = if ($Cancel) { 1 } else { 0 }
                amend = 0
                report = 1
                export = 1
                import = 0
                share = 1
                print = 1
                email = 1
                if_owner = 0
            }
            
            if (-not $doctype.data.permissions) {
                $doctype.data.permissions = @()
            }
            $doctype.data.permissions += $newPerm
        }
        
        # Save the DocType
        $result = Invoke-ErpRequest -Method Put -Path "/api/resource/DocType/$(Enc $DocType)" -Body $doctype.data
        Write-Host "  Success!" -ForegroundColor Green
        
    } catch {
        Write-Host "  Error: $_" -ForegroundColor Red
    }
}

Write-Host "`n=== Setting Permissions for Task ===" -ForegroundColor Cyan

Add-Permission -DocType "Task" -Role "Ops - Order Accepting" -Read $true -Write $true -Create $true
Add-Permission -DocType "Task" -Role "Ops - Order Creating" -Read $true -Write $true -Create $true
Add-Permission -DocType "Task" -Role "Ops - Inventory" -Read $true -Write $true -Create $true
Add-Permission -DocType "Task" -Role "Delivery Driver" -Read $true -Write $true
Add-Permission -DocType "Task" -Role "Ops - Delivery" -Read $true -Write $true
Add-Permission -DocType "Task" -Role "Ops - Returns" -Read $true -Write $true -Create $true
Add-Permission -DocType "Task" -Role "Ops - Accounting" -Read $true -Write $true -Create $true
Add-Permission -DocType "Task" -Role "Ops - Finance" -Read $true -Write $true -Create $true
Add-Permission -DocType "Task" -Role "Ops - Directors" -Read $true -Write $true -Create $true -Delete $true -Submit $true -Cancel $true

Write-Host "`n=== Setting Permissions for Customer ===" -ForegroundColor Cyan

Add-Permission -DocType "Customer" -Role "Ops - Order Accepting" -Read $true
Add-Permission -DocType "Customer" -Role "Ops - Order Creating" -Read $true
Add-Permission -DocType "Customer" -Role "Ops - Inventory" -Read $true
Add-Permission -DocType "Customer" -Role "Delivery Driver" -Read $true
Add-Permission -DocType "Customer" -Role "Ops - Delivery" -Read $true
Add-Permission -DocType "Customer" -Role "Ops - Returns" -Read $true
Add-Permission -DocType "Customer" -Role "Ops - Accounting" -Read $true
Add-Permission -DocType "Customer" -Role "Ops - Finance" -Read $true
Add-Permission -DocType "Customer" -Role "Ops - Directors" -Read $true

Write-Host "`n=== Setting Permissions for Dispatch Case ===" -ForegroundColor Cyan

Add-Permission -DocType "Dispatch Case" -Role "Ops - Order Creating" -Read $true -Write $true -Create $true -Submit $true
Add-Permission -DocType "Dispatch Case" -Role "Ops - Inventory" -Read $true -Write $true
Add-Permission -DocType "Dispatch Case" -Role "Ops - Returns" -Read $true -Write $true
Add-Permission -DocType "Dispatch Case" -Role "Ops - Accounting" -Read $true -Write $true
Add-Permission -DocType "Dispatch Case" -Role "Ops - Finance" -Read $true
Add-Permission -DocType "Dispatch Case" -Role "Ops - Directors" -Read $true -Write $true -Create $true -Delete $true -Submit $true -Cancel $true

Write-Host "`n=== Done! ===" -ForegroundColor Green
Write-Host "Refresh your browser (Ctrl+F5) and try creating a Task." -ForegroundColor Yellow
