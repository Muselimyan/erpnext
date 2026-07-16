$Config  = Get-Content "$PSScriptRoot\export.ps1" -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$H = @{ Authorization = "token ${ApiKey}:${ApiSec}" }

Write-Host "BaseUrl: $BaseUrl"
Write-Host "ApiKey:  $ApiKey"

$r = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Customer?limit_page_length=5&fields=[`"name`",`"customer_name`"]" -Headers $H -Method Get
Write-Host "Customer count (sample): $($r.data.Count)"
$r.data | ForEach-Object { Write-Host "  $($_.name)" }
