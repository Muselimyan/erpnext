$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }

# Re-save both back button Client Scripts to force Frappe cache invalidation
$names = @("Global-Mobile Back Button", "Global-Mobile Back Button List")
foreach ($n in $names) {
    Write-Host "Re-saving '$n' to invalidate cache..."
    $r = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $n)?fields=[`"name`",`"script`"]" -Headers $Headers -Method Get -TimeoutSec 30
    $bodyJson = @{ script = $r.data.script } | ConvertTo-Json -Depth 5 -Compress
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $n)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyJson)) -TimeoutSec 30 | Out-Null
    Write-Host "  -> Saved." -ForegroundColor Green
}
Write-Host "`nBoth scripts re-saved. Cache invalidated." -ForegroundColor Green
Write-Host "Now HARD REFRESH the browser (Ctrl+Shift+R or close/reopen tab)." -ForegroundColor Yellow
