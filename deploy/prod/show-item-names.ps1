param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
)

Set-StrictMode -Off

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config     = Get-Content $ConfigPath -Raw
$BaseUrl    = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey     = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec     = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers    = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

function Enc ([string]$s) { [uri]::EscapeDataString($s) }
function Invoke-ErpRequest { param([string]$Method, [string]$Path, $Body=$null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 120 }
    $Json = $Body | ConvertTo-Json -Depth 40
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 120
}

Write-Host "=== Show Item Names Instead of Item Codes ===" -ForegroundColor Cyan

$DocType = Invoke-ErpRequest -Method Get -Path "/api/resource/DocType/Dispatch%20Case%20Item"

if ($Mode -eq "Deploy") {
    Write-Host "`nMaking changes..." -ForegroundColor Yellow
    
    foreach ($field in $DocType.data.fields) {
        if ($field.fieldname -eq "item_name") {
            $field.in_list_view = 1
            $field.columns = 3
            Write-Host "  item_name: in_list_view = 1" -ForegroundColor Green
        }
        if ($field.fieldname -eq "item_code") {
            $field.in_list_view = 0
            Write-Host "  item_code: in_list_view = 0 (hidden)" -ForegroundColor Green
        }
    }
    
    Write-Host "`nSaving..." -ForegroundColor Yellow
    $Result = Invoke-ErpRequest -Method Put -Path "/api/resource/DocType/Dispatch%20Case%20Item" -Body $DocType.data
    Write-Host "Done!" -ForegroundColor Green
    Write-Host "`nRefresh browser (Ctrl+F5) to see Item Names!" -ForegroundColor Cyan
}
else {
    Write-Host "`nCurrent state:" -ForegroundColor Yellow
    foreach ($field in $DocType.data.fields) {
        if ($field.fieldname -eq "item_name" -or $field.fieldname -eq "item_code") {
            Write-Host "  $($field.fieldname): in_list_view = $($field.in_list_view)" -ForegroundColor Gray
        }
    }
}
