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

$PolicyName = "Debt Closure Approval"
$AfterSaveScriptName = "Task-after-save-debt-closure"
$BeforeSaveScriptName = "Task-before-save-dispatch-gates"
$AfterSaveScriptPath = Join-Path $TestRoot "work\server\Task-after-save-debt-closure.py"
$BeforeSaveScriptPath = Join-Path $TestRoot "work\server\Task-before-save-dispatch-gates.py"
$AfterSaveScript = Get-Content $AfterSaveScriptPath -Raw
$BeforeSaveScript = Get-Content $BeforeSaveScriptPath -Raw

$PolicyExists = $false
$PolicyDefaultUser = ""
$PolicyRoles = @()
try {
    $Policy = Get-ErpDoc "Task Access Policy" $PolicyName
    $PolicyExists = $true
    $PolicyDefaultUser = [string]$Policy.default_team_user
    $PolicyRoles = @($Policy.allowed_roles | ForEach-Object { $_.role })
} catch {}

$DesiredPolicy = @{
    doctype = "Task Access Policy"
    name = $PolicyName
    policy_name = $PolicyName
    default_team_user = "directors.team@example.com"
    allowed_roles = @(
        @{ role = "Ops - Directors" }
    )
}

if ($Mode -eq "Check") {
    [pscustomobject]@{
        target = $BaseUrl
        policy = $PolicyName
        policy_exists = $PolicyExists
        policy_default_team_user = $PolicyDefaultUser
        policy_allowed_roles = $PolicyRoles
        after_save_local_uses_policy = ([string]$AfterSaveScript -match "Task Access Policy")
        before_save_local_uses_policy = ([string]$BeforeSaveScript -match "Task Access Policy")
        after_save_local_has_hardcoded_users = ([string]$AfterSaveScript -match "APPROVED_USERS|ghahramanyann|karapetyansev|vahe\.muselimyan|levonaghinyan")
        before_save_local_has_hardcoded_users = ([string]$BeforeSaveScript -match "APPROVED_USERS|ghahramanyann|karapetyansev|vahe\.muselimyan|levonaghinyan")
    } | ConvertTo-Json
    exit 0
}

Upsert-ErpDoc "Task Access Policy" $PolicyName $DesiredPolicy | Out-Null
Invoke-ErpRequest Put "/api/resource/$(Enc 'Server Script')/$(Enc $AfterSaveScriptName)" @{ script = $AfterSaveScript } | Out-Null
Invoke-ErpRequest Put "/api/resource/$(Enc 'Server Script')/$(Enc $BeforeSaveScriptName)" @{ script = $BeforeSaveScript } | Out-Null

[pscustomobject]@{
    target = $BaseUrl
    policy = $PolicyName
    server_scripts = @($AfterSaveScriptName, $BeforeSaveScriptName)
    status = "updated"
} | ConvertTo-Json
