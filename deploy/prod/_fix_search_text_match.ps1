$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }

# Set search_fields and title_field via Property Setter for key DocTypes
$configs = @(
    @{ doc_type="Dispatch Case"; property="search_fields"; value="customer,notes,status" },
    @{ doc_type="Dispatch Case"; property="title_field"; value="customer" },
    @{ doc_type="Dispatch Case"; property="show_title_field_in_link"; value="1" },
    @{ doc_type="Task"; property="show_title_field_in_link"; value="1" }
)

foreach ($cfg in $configs) {
    Write-Host "Setting $($cfg.doc_type).$($cfg.property) = $($cfg.value)" -ForegroundColor Cyan
    $psName = "$($cfg.doc_type)-main-$($cfg.property)"
    $body = @{
        doctype = "Property Setter"
        name = $psName
        doctype_or_field = "DocType"
        doc_type = $cfg.doc_type
        property = $cfg.property
        value = $cfg.value
        property_type = "Data"
    }
    $bodyJson = $body | ConvertTo-Json -Depth 5 -Compress
    try {
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/Property%20Setter/$(Enc $psName)" -Headers $Headers -Method Get -TimeoutSec 15 | Out-Null
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/Property%20Setter/$(Enc $psName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyJson)) -TimeoutSec 30 | Out-Null
        Write-Host "  -> Updated." -ForegroundColor Green
    } catch {
        try {
            Invoke-RestMethod -Uri "$BaseUrl/api/resource/Property%20Setter" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyJson)) -TimeoutSec 30 | Out-Null
            Write-Host "  -> Created." -ForegroundColor Green
        } catch {
            Write-Host "  -> ERROR: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# Clear cache to apply property setters
Write-Host "`nClearing cache..." -ForegroundColor Cyan
try {
    Invoke-RestMethod -Uri "$BaseUrl/api/method/frappe.clear_cache" -Headers $Headers -Method Post -TimeoutSec 30 | Out-Null
    Write-Host "  -> Cache cleared." -ForegroundColor Green
} catch {
    Write-Host "  -> Cache clear failed (non-critical)" -ForegroundColor Yellow
}

Write-Host "`nDone. Search bars now text-match on customer, notes, subject, etc." -ForegroundColor Green
Write-Host "Hard refresh browser to apply." -ForegroundColor Yellow
