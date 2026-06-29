param()

Set-StrictMode -Off

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config     = Get-Content $ConfigPath -Raw
$BaseUrl    = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey     = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec     = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers    = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

function Invoke-ErpRequest { param([string]$Method, [string]$Path)
    $Uri = "$BaseUrl$Path"
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 120
}

Write-Host "=== Checking Dispatch Case Item Fields ===" -ForegroundColor Cyan

# Get Dispatch Case Item DocType structure
$DocType = Invoke-ErpRequest -Method Get -Path "/api/resource/DocType/Dispatch%20Case%20Item"

Write-Host "`nDispatch Case Item Fields:" -ForegroundColor Yellow
$DocType.data.fields | Where-Object { $_.in_list_view -eq 1 -or $_.fieldname -like "*item*" } | ForEach-Object {
    Write-Host "  - Fieldname: $($_.fieldname)" -ForegroundColor White
    Write-Host "    Label: $($_.label)" -ForegroundColor Gray
    Write-Host "    Type: $($_.fieldtype)" -ForegroundColor Gray
    Write-Host "    In List View: $($_.in_list_view)" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "`nAll fields in list view:" -ForegroundColor Yellow
$DocType.data.fields | Where-Object { $_.in_list_view -eq 1 } | ForEach-Object {
    Write-Host "  $($_.fieldname) - $($_.label)" -ForegroundColor Gray
}
