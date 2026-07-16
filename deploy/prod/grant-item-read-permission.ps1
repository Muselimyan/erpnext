param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
)

Set-StrictMode -Off

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config     = Get-Content $ConfigPath -Raw
$BaseUrl    = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey     = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec     = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers    = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json"; "User-Agent" = "Mozilla/5.0" }

function Enc ([string]$s) { [uri]::EscapeDataString($s) }
function Invoke-ErpRequest { param([string]$Method, [string]$Path, $Body=$null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 120 }
    $Json = $Body | ConvertTo-Json -Depth 40
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 120
}
function Get-ErpDoc { param([string]$DocType,[string]$Name)
    try { return (Invoke-ErpRequest -Method Get -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)").data } catch { return $null }
}
function Upsert-ErpDoc { param([string]$DocType,[string]$Name,$Body)
    $Existing = Get-ErpDoc $DocType $Name
    if ($null -eq $Existing) { $Body.name=$Name; $C=(Invoke-ErpRequest Post "/api/resource/$(Enc $DocType)" $Body).data; return [pscustomobject]@{action="created";name=$C.name} }
    $U=(Invoke-ErpRequest Put "/api/resource/$(Enc $DocType)/$(Enc $Name)" $Body).data; return [pscustomobject]@{action="updated";name=$U.name}
}

Write-Host "=== Granting Item Read Permission to Operational Roles ===" -ForegroundColor Cyan

$Roles = @(
    "Ops - Order Creating",
    "Ops - Order Accepting",
    "Ops - Inventory",
    "Ops - Returns",
    "Ops - Accounting",
    "Ops - Finance",
    "Ops - Directors",
    "Delivery Driver"
)

$Report = [ordered]@{ mode=$Mode; permissions=@() }

foreach ($role in $Roles) {
    $PermName = "Item-$role-0"
    $PermBody = [ordered]@{
        parent = "Item"
        parenttype = "DocType"
        parentfield = "permissions"
        role = $role
        permlevel = 0
        read = 1
        write = 0
        create = 0
        delete = 0
        submit = 0
        cancel = 0
        amend = 0
        report = 1
        export = 0
        import = 0
        set_user_permissions = 0
        share = 0
        print = 1
        email = 0
    }
    
    if ($Mode -eq "Deploy") {
        try {
            $Result = Upsert-ErpDoc -DocType "Custom DocPerm" -Name $PermName -Body $PermBody
            $Report.permissions += [pscustomobject]@{
                role = $role
                action = $Result.action
                name = $Result.name
            }
            Write-Host "  $role : $($Result.action)" -ForegroundColor Green
        } catch {
            Write-Host "  $role : ERROR - $_" -ForegroundColor Red
            $Report.permissions += [pscustomobject]@{
                role = $role
                action = "error"
                error = $_.Exception.Message
            }
        }
    } else {
        $Existing = Get-ErpDoc -DocType "Custom DocPerm" -Name $PermName
        $Report.permissions += [pscustomobject]@{
            role = $role
            exists = ($null -ne $Existing)
        }
        if ($null -ne $Existing) {
            Write-Host "  $role : exists" -ForegroundColor Yellow
        } else {
            Write-Host "  $role : missing" -ForegroundColor Red
        }
    }
}

$Report | ConvertTo-Json -Depth 10
