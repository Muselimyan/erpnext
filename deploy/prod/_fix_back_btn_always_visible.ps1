$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }

$names = @("Global-Mobile Back Button", "Global-Mobile Back Button List")
foreach ($n in $names) {
    Write-Host "`nProcessing: $n" -ForegroundColor Cyan
    $r = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $n)?fields=[`"name`",`"script`"]" -Headers $Headers -Method Get -TimeoutSec 30
    $original = $r.data.script
    $fixed = $original

    # Remove the isHome block that hides the button on home/workspace pages
    # Pattern 1 (form script): multi-line isHome var + if block
    $fixed = $fixed -replace '(?s)\s*var isHome = url\.endsWith.*?if \(isHome\)\s*\{[^}]*\}\s*\r?\n?\s*return;\s*\r?\n?\s*\}', ''
    # Pattern 2 (list script): single-line isHome + hide
    $fixed = $fixed -replace '(?s)\s*var isHome = url\.endsWith.*?if \(isHome\)\s*\{[^}]*\}\s*', ''

    # Also remove the url variable if it is now unused (only used for isHome)
    # Check if url is still referenced after removing isHome
    if ($fixed -notmatch 'url\.' -and $fixed -notmatch '\burl\b.*==' ) {
        $fixed = $fixed -replace "\s*var url = window\.location\.href\.toLowerCase\(\);\s*", "`n"
    }

    if ($fixed -eq $original) {
        Write-Host "  -> No isHome block found, already clean." -ForegroundColor Green
        continue
    }

    $bodyJson = @{ script = $fixed } | ConvertTo-Json -Depth 5 -Compress
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $n)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyJson)) -TimeoutSec 30 | Out-Null
    Write-Host "  -> Removed isHome hide logic. Button now visible on ALL pages." -ForegroundColor Green
}
Write-Host "`nDone. Hard refresh the browser to see the change." -ForegroundColor Green
