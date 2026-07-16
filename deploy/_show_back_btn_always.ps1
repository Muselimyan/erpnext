$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

function Enc([string]$s) { [uri]::EscapeDataString($s) }

# Fetch all enabled Client Scripts that contain the back button code
$r = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script?filters=%5B%5B%22enabled%22%2C%22%3D%22%2C1%5D%5D&fields=%5B%22name%22%2C%22script%22%5D&limit_page_length=200" -Headers $Headers -Method Get -TimeoutSec 30
$scripts = @($r.data | Where-Object { $_.script -and $_.script.Contains('mobile-back-btn') })
Write-Host "Found $($scripts.Count) Client Script(s) with back button code"

foreach ($cs in $scripts) {
    Write-Host "`nProcessing: $($cs.name)"
    $original = $cs.script
    $needle = "if (window.innerWidth > 768) { if (btn) btn.style.display = 'none'; return; }"
    if (-not $original.Contains($needle)) {
        Write-Host "  -> Does not contain the desktop-hide line, skipping." -ForegroundColor Yellow
        continue
    }
    # Remove the line that hides on desktop
    $fixed = $original.Replace($needle, "")
    $bodyJson = @{ script = $fixed } | ConvertTo-Json -Depth 5 -Compress
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $cs.name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyJson)) -TimeoutSec 30 | Out-Null
    Write-Host "  -> Removed desktop-hide check. Button now always visible." -ForegroundColor Green
}
Write-Host "`nDone." -ForegroundColor Green
