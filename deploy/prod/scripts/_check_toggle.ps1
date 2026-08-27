$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

$r = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/Global-Mobile%20Back%20Button%20List" -Headers $Headers -Method Get -TimeoutSec 30).data
Write-Host "dt=$($r.dt) view=$($r.view) enabled=$($r.enabled) script_len=$($r.script.Length)"
Write-Host "First 200 chars of script:"
Write-Host $r.script.Substring(0, [Math]::Min(200, $r.script.Length))
Write-Host "---"
Write-Host "Last 300 chars of script:"
Write-Host $r.script.Substring([Math]::Max(0, $r.script.Length - 300))
