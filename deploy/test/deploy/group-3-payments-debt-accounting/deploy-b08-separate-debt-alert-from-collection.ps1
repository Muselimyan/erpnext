param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$TestRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ConfigPath = Join-Path $TestRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

function Enc([string]$s) { [uri]::EscapeDataString($s) }
function Invoke-ErpRequest { param([string]$Method, [string]$Path, $Body=$null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 120 }
    $Json = $Body | ConvertTo-Json -Depth 80
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 120
}
function Get-ErpDoc { param([string]$DocType, [string]$Name)
    return (Invoke-ErpRequest Get "/api/resource/$(Enc $DocType)/$(Enc $Name)").data
}
function Upsert-ErpDoc { param([string]$DocType, [string]$Name, $Doc)
    try {
        Get-ErpDoc $DocType $Name | Out-Null
        $Body = @{}
        foreach ($Key in $Doc.Keys) { if ($Key -ne "doctype" -and $Key -ne "name") { $Body[$Key] = $Doc[$Key] } }
        return (Invoke-ErpRequest Put "/api/resource/$(Enc $DocType)/$(Enc $Name)" $Body).data
    } catch {
        return (Invoke-ErpRequest Post "/api/resource/$(Enc $DocType)" $Doc).data
    }
}

$DebtAlertKind = "Debt Alert"
$ServerScriptName = "Scheduled-debt-collection"
$ServerScriptPath = Join-Path $TestRoot "work\server\Scheduled-debt-collection.py"
$LocalScript = Get-Content $ServerScriptPath -Raw
$TaskKindField = Get-ErpDoc "Custom Field" "Task-task_kind"
$CurrentScript = Get-ErpDoc "Server Script" $ServerScriptName
$CurrentOptions = [string]$TaskKindField.options
$HasDebtAlertOption = (($CurrentOptions -split "`n") -contains $DebtAlertKind)
$DebtAlertPolicyExists = $false
try { Get-ErpDoc "Task Access Policy" $DebtAlertKind | Out-Null; $DebtAlertPolicyExists = $true } catch {}

$DebtAlertPolicy = @{
    doctype = "Task Access Policy"
    name = $DebtAlertKind
    policy_name = $DebtAlertKind
    default_team_user = "directors.team@example.com"
    allowed_roles = @(
        @{ role = "Ops - Directors" }
    )
}

if ($Mode -eq "Check") {
    [pscustomobject]@{
        target = $BaseUrl
        task_kind_has_debt_alert = $HasDebtAlertOption
        debt_alert_policy_exists = $DebtAlertPolicyExists
        scheduled_script = $CurrentScript.name
        scheduled_script_disabled = $CurrentScript.disabled
        live_uses_debt_alert = ([string]$CurrentScript.script -match "Debt Alert")
        local_uses_debt_alert = ([string]$LocalScript -match "Debt Alert")
        local_avoids_debt_collection_kind = -not ([string]$LocalScript -match 'task_kind"\s*:\s*"Debt Collection"')
    } | ConvertTo-Json
    exit 0
}

if (-not $HasDebtAlertOption) {
    $NewOptions = (($CurrentOptions.TrimEnd() -split "`n") + $DebtAlertKind) -join "`n"
    Invoke-ErpRequest Put "/api/resource/$(Enc 'Custom Field')/$(Enc 'Task-task_kind')" @{ options = $NewOptions } | Out-Null
}
Upsert-ErpDoc "Task Access Policy" $DebtAlertKind $DebtAlertPolicy | Out-Null
Invoke-ErpRequest Put "/api/resource/$(Enc 'Server Script')/$(Enc $ServerScriptName)" @{ script = $LocalScript } | Out-Null

[pscustomobject]@{
    target = $BaseUrl
    task_kind = $DebtAlertKind
    task_access_policy = $DebtAlertKind
    server_script = $ServerScriptName
    status = "updated"
} | ConvertTo-Json
