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
        return Get-ErpList -DocType "Custom DocPerm" -Fields @("name", "role", "parent", "read") -Filters $Filters -Limit 5
    } catch {
        return $null
    }
}

function Grant-ReadPermission {
    param(
        [string]$RoleName,
        [string]$DocTypeName
    )

    Write-Host "  Granting READ to $RoleName on $DocTypeName..." -NoNewline

    $Existing = Get-CustomDocPerms -RoleName $RoleName -DocTypeName $DocTypeName

    $Body = [ordered]@{
        doctype     = "Custom DocPerm"
        role        = $RoleName
        parent      = $DocTypeName
        parenttype  = "DocType"
        parentfield = "permissions"
        permlevel   = 0
        read        = 1
        write       = 0
        create      = 0
        delete      = 0
        submit      = 0
        cancel      = 0
        amend       = 0
        report      = 1
        export      = 0
        print       = 0
        email       = 0
        share       = 0
    }

    try {
        if ($Existing -and $Existing.Count -gt 0) {
            Write-Host " already exists" -ForegroundColor Yellow
        } else {
            $Created = (Invoke-ErpRequest -Method Post -Path "/api/resource/$(Enc 'Custom DocPerm')" -Body $Body).data
            Write-Host " created" -ForegroundColor Green
        }
    } catch {
        Write-Host " ERROR" -ForegroundColor Red
    }
}

Write-Host "`n=== Granting READ permission on Collection Set ===" -ForegroundColor Cyan

Grant-ReadPermission -RoleName "Ops - Order Accepting" -DocTypeName "Collection Set"
Grant-ReadPermission -RoleName "Ops - Order Creating" -DocTypeName "Collection Set"
Grant-ReadPermission -RoleName "Ops - Inventory" -DocTypeName "Collection Set"
Grant-ReadPermission -RoleName "Ops - Returns" -DocTypeName "Collection Set"
Grant-ReadPermission -RoleName "Ops - Accounting" -DocTypeName "Collection Set"
Grant-ReadPermission -RoleName "Ops - Directors" -DocTypeName "Collection Set"

Write-Host "`n=== Done! ===" -ForegroundColor Green
Write-Host "Refresh your browser and the Collection Set error should be gone." -ForegroundColor Yellow
