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

Write-Host "=== Finding ALL Task Custom Fields with 'assign' in name or label ===" -ForegroundColor Cyan

$AllFields = Invoke-ErpRequest -Method Get -Path "/api/resource/Custom Field?filters=[[%22dt%22,%22=%22,%22Task%22]]&fields=[%22name%22,%22fieldname%22,%22label%22,%22insert_after%22]&limit_page_length=500"

Write-Host "`nTask Custom Fields containing 'assign':" -ForegroundColor Yellow
$AllFields.data | Where-Object { 
    $_.fieldname -like "*assign*" -or $_.label -like "*assign*" 
} | ForEach-Object {
    Write-Host "  - Name: $($_.name)" -ForegroundColor White
    Write-Host "    Fieldname: $($_.fieldname)" -ForegroundColor Gray
    Write-Host "    Label: $($_.label)" -ForegroundColor Gray
    Write-Host "    Insert After: $($_.insert_after)" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "=== All Task Custom Fields (for reference) ===" -ForegroundColor Cyan
$AllFields.data | Sort-Object insert_after | ForEach-Object {
    Write-Host "$($_.fieldname) - $($_.label) (after: $($_.insert_after))" -ForegroundColor Gray
}
