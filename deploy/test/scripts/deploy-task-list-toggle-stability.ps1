Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
if ($BaseUrl -ne "https://test.erpnext.am") { throw "Refusing non-test target: $BaseUrl" }
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }
function Put-ClientScript([string]$Name, [string]$Path) {
    $Script = Get-Content $Path -Raw
    $Body = @{ dt = "Task"; view = "List"; enabled = 1; script = $Script } | ConvertTo-Json -Depth 50
    $Uri = "$BaseUrl/api/resource/$(Enc 'Client Script')/$(Enc $Name)"
    $Result = Invoke-RestMethod -Uri $Uri -Headers $Headers -Method Put -Body ([Text.Encoding]::UTF8.GetBytes($Body)) -TimeoutSec 45
    [pscustomobject]@{
        updated = $Result.data.name
        has_dedicated_flag = ([string]$Result.data.script -match '_taskToggleDedicated')
        has_stability_marker = ([string]$Result.data.script -match 'data-task-toggle-stable')
        has_observer = ([string]$Result.data.script -match 'MutationObserver')
    }
}

$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Results = @()
$Results += Put-ClientScript "Task-List Toggle Filters" (Join-Path $Root "_live_Task_List_Toggle_Filters_test.js")
$Results += Put-ClientScript "Global-Mobile Back Button List" (Join-Path $Root "_live_Global_Mobile_Back_Button_List_test.js")
[pscustomobject]@{ target = $BaseUrl; results = $Results } | ConvertTo-Json -Depth 10
