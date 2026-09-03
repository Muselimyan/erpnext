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

$ServerScriptName = "Task-after-save-debt-closure"
$ServerScriptPath = Join-Path $TestRoot "work\server\Task-after-save-debt-closure.py"
$LocalScript = Get-Content $ServerScriptPath -Raw
$Current = (Invoke-ErpRequest Get "/api/resource/$(Enc 'Server Script')/$(Enc $ServerScriptName)?fields=$(Enc '["name","disabled","script"]')").data

if ($Mode -eq "Check") {
    [pscustomobject]@{
        target = $BaseUrl
        server_script = $Current.name
        disabled = $Current.disabled
        live_uses_open_invoices_for_profit = ([string]$Current.script -match "invoice_rows" -and [string]$Current.script -match "doc\.open_invoices")
        local_uses_open_invoices_for_profit = ([string]$LocalScript -match "invoice_rows" -and [string]$LocalScript -match "doc\.open_invoices")
        local_sets_each_dispatch_case_profit = ([string]$LocalScript -match "dispatch_case_profit")
    } | ConvertTo-Json
    exit 0
}

$Updated = (Invoke-ErpRequest Put "/api/resource/$(Enc 'Server Script')/$(Enc $ServerScriptName)" @{ script = $LocalScript }).data
[pscustomobject]@{
    target = $BaseUrl
    updated = $Updated.name
    modified = $Updated.modified
    status = "updated"
} | ConvertTo-Json
