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

Write-Host "=== Deleting Task-custom_assigned_to Field ===" -ForegroundColor Cyan

try {
    Write-Host "Deleting 'Task-custom_assigned_to' custom field..." -ForegroundColor Yellow
    $Result = Invoke-ErpRequest -Method Delete -Path "/api/resource/Custom Field/Task-custom_assigned_to"
    Write-Host "SUCCESS: Field deleted!" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Could not delete field: $_" -ForegroundColor Red
    throw
}

Write-Host "`n=== Done! ===" -ForegroundColor Cyan
Write-Host "The 'Assigned To' field in the barcode scanning section is now DELETED." -ForegroundColor White
Write-Host "Refresh your browser (Ctrl+F5) to see the change." -ForegroundColor White
