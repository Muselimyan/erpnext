$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }

$r = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script?filters=%5B%5B%22enabled%22%2C%22%3D%22%2C1%5D%5D&fields=%5B%22name%22%2C%22script%22%5D&limit_page_length=200" -Headers $Headers -Method Get -TimeoutSec 30
$scripts = @($r.data | Where-Object { $_.script -and $_.script.Contains('mobile-back-btn') })

foreach ($cs in $scripts) {
    Write-Host "`n========== $($cs.name) ==========" -ForegroundColor Cyan
    $cs.script
    Write-Host "`n"
}
