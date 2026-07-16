$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }
foreach ($n in @("Task-Accept Start", "Task-Lock Unaccepted")) {
    Write-Host "`n=== $n ===" -ForegroundColor Cyan
    $r = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $n)?fields=[`"script`"]" -Headers $Headers -Method Get -TimeoutSec 30
    $r.data.script
}
