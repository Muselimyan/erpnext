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

# Custom field for Assigned To on Task
$AssignedToField = [ordered]@{
    name = "Task-custom_assigned_to"
    dt = "Task"
    fieldname = "custom_assigned_to"
    label = "Assigned To"
    fieldtype = "Link"
    options = "User"
    insert_after = "status"
}

$Report = [ordered]@{ mode=$Mode; custom_fields=@(); notes=@() }

# Deploy/Check Assigned To field
$Existing = Get-ErpDoc -DocType "Custom Field" -Name $AssignedToField.name
if ($Mode -eq "Deploy") {
    $Report.custom_fields += Upsert-ErpDoc -DocType "Custom Field" -Name $AssignedToField.name -Body $AssignedToField
} else {
    $Report.custom_fields += [pscustomobject]@{ name=$AssignedToField.name; exists=($null -ne $Existing) }
}

$Report.notes += "Adds visible Assigned To field on Task form for easy assignment."
$Report.notes += "Field appears right after Status field."

$Report | ConvertTo-Json -Depth 30
