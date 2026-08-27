param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

function Enc([string]$s) { [uri]::EscapeDataString($s) }
function Invoke-ErpRequest { param([string]$Method, [string]$Path, $Body=$null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 120 }
    $Json = $Body | ConvertTo-Json -Depth 60
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 120
}

$ServerScriptName = "Task-after-save-dispatch-flow"
$ScriptPath = Join-Path $PSScriptRoot "_live_Task_after_save_dispatch_flow_test.py"
$Current = (Invoke-ErpRequest Get "/api/resource/$(Enc 'Server Script')/$(Enc $ServerScriptName)?fields=$(Enc '["name","disabled","script"]')").data

if ($Mode -eq "Check") {
    [pscustomobject]@{
        target = $BaseUrl
        server_script = $Current.name
        disabled = $Current.disabled
        live_has_customer_guard = ([string]$Current.script -match "Set Customer on Dispatch Case")
        local_patch_exists = Test-Path $ScriptPath
    } | ConvertTo-Json
    exit 0
}

if (!(Test-Path $ScriptPath)) { throw "Missing local patched script: $ScriptPath" }
$PatchedScript = Get-Content $ScriptPath -Raw
$Updated = (Invoke-ErpRequest Put "/api/resource/$(Enc 'Server Script')/$(Enc $ServerScriptName)" @{ script = $PatchedScript }).data
[pscustomobject]@{
    target = $BaseUrl
    updated = $Updated.name
    modified = $Updated.modified
    live_has_customer_guard = ([string]$Updated.script -match "Set Customer on Dispatch Case")
} | ConvertTo-Json
