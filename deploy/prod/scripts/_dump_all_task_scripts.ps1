$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)" }
$r = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script?filters=%5B%5B%22dt%22%2C%22%3D%22%2C%22Task%22%5D%2C%5B%22view%22%2C%22%3D%22%2C%22Form%22%5D%2C%5B%22enabled%22%2C%22%3D%22%2C1%5D%5D&fields=%5B%22name%22%2C%22script%22%5D&limit_page_length=50" -Headers $Headers -Method Get -TimeoutSec 30
foreach ($cs in $r.data) {
    Write-Host "=== $($cs.name) ===" -ForegroundColor Cyan
    $lines = $cs.script -split "`n"
    for ($i=0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match 'clear_custom_buttons|custom_buttons|inner_toolbar|Accept|accept') {
            Write-Host "  L$($i+1): $($lines[$i].TrimEnd())" -ForegroundColor Yellow
        }
    }
}
