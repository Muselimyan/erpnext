$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)" }

# Check System Settings for search-related fields
Write-Host "=== System Settings (search-related) ===" -ForegroundColor Cyan
$ss = Invoke-RestMethod -Uri "$BaseUrl/api/resource/System%20Settings/System%20Settings" -Headers $Headers -Method Get -TimeoutSec 30
$searchFields = $ss.data.PSObject.Properties | Where-Object { $_.Name -match 'search|filter' }
foreach ($f in $searchFields) {
    Write-Host "  $($f.Name) = $($f.Value)"
}

# Check if global search is enabled
Write-Host "`n=== Website Settings (search) ===" -ForegroundColor Cyan
try {
    $ws = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Website%20Settings/Website%20Settings" -Headers $Headers -Method Get -TimeoutSec 30
    $wsSearch = $ws.data.PSObject.Properties | Where-Object { $_.Name -match 'search' }
    foreach ($f in $wsSearch) {
        Write-Host "  $($f.Name) = $($f.Value)"
    }
} catch { Write-Host "  (not accessible)" }

# Check search_fields for key DocTypes
Write-Host "`n=== Search Fields on key DocTypes ===" -ForegroundColor Cyan
foreach ($dt in @("Task", "Item", "Dispatch Case", "Customer", "Supplier")) {
    try {
        $meta = Invoke-RestMethod -Uri "$BaseUrl/api/method/frappe.client.get_list?doctype=DocType&filters=%5B%5B%22name%22%2C%22%3D%22%2C%22$([uri]::EscapeDataString($dt))%22%5D%5D&fields=%5B%22name%22%2C%22search_fields%22%2C%22title_field%22%2C%22show_title_field_in_link%22%5D" -Headers $Headers -Method Get -TimeoutSec 15
        $d = $meta.message[0]
        Write-Host "  $dt -> search_fields='$($d.search_fields)' title_field='$($d.title_field)' show_title='$($d.show_title_field_in_link)'"
    } catch {
        Write-Host "  $dt -> (error fetching)" -ForegroundColor Red
    }
}
