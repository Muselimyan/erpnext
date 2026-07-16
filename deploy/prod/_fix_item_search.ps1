$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }

# 1. Enable show_title_field_in_link for Item so item_name shows in search results
Write-Host "Setting Item.show_title_field_in_link = 1" -ForegroundColor Cyan
$psName = "Item-main-show_title_field_in_link"
$body = @{
    doctype = "Property Setter"
    name = $psName
    doctype_or_field = "DocType"
    doc_type = "Item"
    property = "show_title_field_in_link"
    value = "1"
    property_type = "Check"
} | ConvertTo-Json -Depth 5 -Compress
try {
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Property%20Setter/$(Enc $psName)" -Headers $Headers -Method Get -TimeoutSec 10 | Out-Null
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Property%20Setter/$(Enc $psName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 15 | Out-Null
    Write-Host "  -> Updated." -ForegroundColor Green
} catch {
    try {
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/Property%20Setter" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 15 | Out-Null
        Write-Host "  -> Created." -ForegroundColor Green
    } catch { Write-Host "  -> ERROR: $($_.Exception.Message)" -ForegroundColor Red }
}

# 2. Check for any Client Scripts that override item search with set_query
Write-Host "`nChecking for custom item search overrides..." -ForegroundColor Cyan
$r = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script?filters=%5B%5B%22enabled%22%2C%22%3D%22%2C1%5D%5D&fields=%5B%22name%22%2C%22script%22%5D&limit_page_length=200" -Headers $Headers -Method Get -TimeoutSec 60
foreach ($cs in $r.data) {
    if ($cs.script -and ($cs.script -match 'set_query.*item' -or $cs.script -match 'get_query.*item')) {
        $lines = $cs.script -split "`n"
        for ($i=0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match 'set_query|get_query') {
                Write-Host "  $($cs.name) L$($i+1): $($lines[$i].TrimEnd())" -ForegroundColor Yellow
            }
        }
    }
}

# 3. Clear cache
Write-Host "`nClearing cache..." -ForegroundColor Cyan
try {
    Invoke-RestMethod -Uri "$BaseUrl/api/method/frappe.clear_cache" -Headers $Headers -Method Post -TimeoutSec 30 | Out-Null
    Write-Host "  -> Done." -ForegroundColor Green
} catch { Write-Host "  -> (non-critical)" -ForegroundColor Yellow }

Write-Host "`nItem search now shows item names and matches by text." -ForegroundColor Green
