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

function Get-ErpList {
    param([string]$DocType, [array]$Fields, [array]$Filters, [int]$Limit=100)
    $FieldsJson = ($Fields | ConvertTo-Json -Compress)
    $FiltersJson = ($Filters | ConvertTo-Json -Compress -Depth 10)
    $Uri = "$BaseUrl/api/resource/$($DocType)?fields=$(Enc $FieldsJson)&filters=$(Enc $FiltersJson)&limit_page_length=$Limit"
    return (Invoke-RestMethod -Uri $Uri -Headers $Headers -Method Get -TimeoutSec 30).data
}

function Get-CustomDocPerms {
    param([string]$RoleName, [string]$DocTypeName)
    $Filters = @(
        @("role",   "=", $RoleName),
        @("parent", "=", $DocTypeName)
    )
    try {
        return Get-ErpList -DocType "Custom DocPerm" -Fields @("name", "role", "parent", "read", "write", "create", "delete", "submit", "cancel") -Filters $Filters -Limit 5
    } catch {
        return $null
    }
}

function Grant-Permission {
    param(
        [string]$RoleName,
        [string]$DocTypeName,
        [int]$Read = 0,
        [int]$Write = 0,
        [int]$Create = 0,
        [int]$Delete = 0,
        [int]$Submit = 0,
        [int]$Cancel = 0
    )

    Write-Host "  Granting $RoleName on $DocTypeName..." -NoNewline

    $Existing = Get-CustomDocPerms -RoleName $RoleName -DocTypeName $DocTypeName

    $Body = [ordered]@{
        doctype     = "Custom DocPerm"
        role        = $RoleName
        parent      = $DocTypeName
        parenttype  = "DocType"
        parentfield = "permissions"
        permlevel   = 0
        read        = $Read
        write       = $Write
        create      = $Create
        delete      = $Delete
        submit      = $Submit
        cancel      = $Cancel
        amend       = 0
        report      = 1
        export      = 1
        print       = 1
        email       = 1
        share       = 1
    }

    try {
        if ($Existing -and $Existing.Count -gt 0) {
            $ExistingName = $Existing[0].name
            $Updated = (Invoke-ErpRequest -Method Put -Path "/api/resource/$(Enc 'Custom DocPerm')/$(Enc $ExistingName)" -Body $Body).data
            Write-Host " updated" -ForegroundColor Green
        } else {
            $Created = (Invoke-ErpRequest -Method Post -Path "/api/resource/$(Enc 'Custom DocPerm')" -Body $Body).data
            Write-Host " created" -ForegroundColor Green
        }
    } catch {
        Write-Host " ERROR: $_" -ForegroundColor Red
    }
}

Write-Host "`n=== Granting Task Permissions ===" -ForegroundColor Cyan
Grant-Permission -RoleName "Ops - Order Accepting" -DocTypeName "Task" -Read 1 -Write 1 -Create 1
Grant-Permission -RoleName "Ops - Order Creating" -DocTypeName "Task" -Read 1 -Write 1 -Create 1
Grant-Permission -RoleName "Ops - Inventory" -DocTypeName "Task" -Read 1 -Write 1 -Create 1
Grant-Permission -RoleName "Delivery Driver" -DocTypeName "Task" -Read 1 -Write 1
Grant-Permission -RoleName "Ops - Delivery" -DocTypeName "Task" -Read 1 -Write 1
Grant-Permission -RoleName "Ops - Returns" -DocTypeName "Task" -Read 1 -Write 1 -Create 1
Grant-Permission -RoleName "Ops - Accounting" -DocTypeName "Task" -Read 1 -Write 1 -Create 1
Grant-Permission -RoleName "Ops - Finance" -DocTypeName "Task" -Read 1 -Write 1 -Create 1
Grant-Permission -RoleName "Ops - Directors" -DocTypeName "Task" -Read 1 -Write 1 -Create 1 -Delete 1 -Submit 1 -Cancel 1

Write-Host "`n=== Granting Customer Permissions ===" -ForegroundColor Cyan
Grant-Permission -RoleName "Ops - Order Accepting" -DocTypeName "Customer" -Read 1
Grant-Permission -RoleName "Ops - Order Creating" -DocTypeName "Customer" -Read 1
Grant-Permission -RoleName "Ops - Inventory" -DocTypeName "Customer" -Read 1
Grant-Permission -RoleName "Delivery Driver" -DocTypeName "Customer" -Read 1
Grant-Permission -RoleName "Ops - Delivery" -DocTypeName "Customer" -Read 1
Grant-Permission -RoleName "Ops - Returns" -DocTypeName "Customer" -Read 1
Grant-Permission -RoleName "Ops - Accounting" -DocTypeName "Customer" -Read 1
Grant-Permission -RoleName "Ops - Finance" -DocTypeName "Customer" -Read 1
Grant-Permission -RoleName "Ops - Directors" -DocTypeName "Customer" -Read 1

Write-Host "`n=== Granting Dispatch Case Permissions ===" -ForegroundColor Cyan
Grant-Permission -RoleName "Ops - Order Creating" -DocTypeName "Dispatch Case" -Read 1 -Write 1 -Create 1 -Submit 1
Grant-Permission -RoleName "Ops - Inventory" -DocTypeName "Dispatch Case" -Read 1 -Write 1
Grant-Permission -RoleName "Ops - Returns" -DocTypeName "Dispatch Case" -Read 1 -Write 1
Grant-Permission -RoleName "Ops - Accounting" -DocTypeName "Dispatch Case" -Read 1 -Write 1
Grant-Permission -RoleName "Ops - Finance" -DocTypeName "Dispatch Case" -Read 1
Grant-Permission -RoleName "Ops - Directors" -DocTypeName "Dispatch Case" -Read 1 -Write 1 -Create 1 -Delete 1 -Submit 1 -Cancel 1

Write-Host "`n=== Done! ===" -ForegroundColor Green
Write-Host "Permissions granted via Custom DocPerm." -ForegroundColor Yellow
Write-Host "Refresh your browser (Ctrl+F5) and try again!" -ForegroundColor Yellow
