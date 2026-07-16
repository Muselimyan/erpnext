$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }
$r = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc 'Global-Mobile Back Button')?fields=[`"script`"]" -Headers $Headers -Method Get -TimeoutSec 30
$script = $r.data.script
# Show lines containing "768" or "innerWidth"
$lines = $script -split "`n"
for ($i=0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '768|innerWidth') {
        Write-Host "Line $($i+1): $($lines[$i])"
    }
}
