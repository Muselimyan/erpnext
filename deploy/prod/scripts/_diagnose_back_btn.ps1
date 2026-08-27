$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)" }

# Fetch ALL enabled Client Scripts
$r = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script?filters=%5B%5B%22enabled%22%2C%22%3D%22%2C1%5D%5D&fields=%5B%22name%22%2C%22dt%22%2C%22view%22%2C%22script%22%5D&limit_page_length=500" -Headers $Headers -Method Get -TimeoutSec 60

Write-Host "Total enabled Client Scripts: $($r.data.Count)" -ForegroundColor Cyan

# Check ALL scripts for back button related code
$keywords = @('mobile-back-btn', 'back-btn', 'backBtn', 'back_btn', 'innerWidth', '768', 'ensureBackBtn', 'buildMobileBackButton', '_mobileBackInterval', '_backBtnWired')

foreach ($cs in $r.data) {
    if (-not $cs.script) { continue }
    $found = @()
    foreach ($kw in $keywords) {
        if ($cs.script.Contains($kw)) { $found += $kw }
    }
    if ($found.Count -gt 0) {
        Write-Host "`n=== $($cs.name) (dt=$($cs.dt), view=$($cs.view)) ===" -ForegroundColor Yellow
        Write-Host "  Keywords: $($found -join ', ')"
        # Show lines with these keywords
        $lines = $cs.script -split "`n"
        for ($i=0; $i -lt $lines.Count; $i++) {
            foreach ($kw in $found) {
                if ($lines[$i].Contains($kw)) {
                    Write-Host "  L$($i+1): $($lines[$i].TrimEnd())"
                    break
                }
            }
        }
    }
}
Write-Host "`nDone." -ForegroundColor Green
