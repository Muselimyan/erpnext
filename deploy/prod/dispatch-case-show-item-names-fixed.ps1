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

Write-Host "=== Dispatch Case - Show Item Names Instead of Item Codes ===" -ForegroundColor Cyan

if ($Mode -eq "Deploy") {
    Write-Host "`nStep 1: Making Item Name visible in list view..." -ForegroundColor Yellow
    
    # Get the DocType
    $DocType = Invoke-ErpRequest -Method Get -Path "/api/resource/DocType/Dispatch%20Case%20Item"
    
    # Find and update the item_name field
    $itemNameField = $DocType.data.fields | Where-Object { $_.fieldname -eq "item_name" }
    if ($itemNameField) {
        $itemNameField.in_list_view = 1
        $itemNameField.columns = 3  # Give it more width
        Write-Host "  âœ“ Set item_name.in_list_view = 1" -ForegroundColor Green
    }
    
    # Find and update the item_code field - hide it from list view
    $itemCodeField = $DocType.data.fields | Where-Object { $_.fieldname -eq "item_code" }
    if ($itemCodeField) {
        $itemCodeField.in_list_view = 0
        Write-Host "  âœ“ Set item_code.in_list_view = 0 (hidden)" -ForegroundColor Green
    }
    
    Write-Host "`nStep 2: Saving DocType changes..." -ForegroundColor Yellow
    
    # Save the DocType
    try {
        $Result = Invoke-ErpRequest -Method Put -Path "/api/resource/DocType/Dispatch%20Case%20Item" -Body $DocType.data
        Write-Host "  âœ“ DocType updated successfully!" -ForegroundColor Green
    }
    catch {
        Write-Host "  âœ— Error updating DocType: $_" -ForegroundColor Red
        throw
    }
    
    Write-Host "`n=== Done! ===" -ForegroundColor Cyan
    Write-Host "Changes applied:" -ForegroundColor White
    Write-Host "  - Item Name is now VISIBLE in Dispatch Case items table" -ForegroundColor Green
    Write-Host "  - Item Code is now HIDDEN from list view" -ForegroundColor Green
    Write-Host "`nNext steps:" -ForegroundColor Yellow
    Write-Host "  1. Refresh your browser (Ctrl+F5)" -ForegroundColor White
    Write-Host "  2. Open a Dispatch Case" -ForegroundColor White
    Write-Host "  3. You should see Item Names instead of Item Codes!" -ForegroundColor White
    
} else {
    Write-Host "`nChecking current state..." -ForegroundColor Yellow
    
    $DocType = Invoke-ErpRequest -Method Get -Path "/api/resource/DocType/Dispatch%20Case%20Item"
    
    $itemNameField = $DocType.data.fields | Where-Object { $_.fieldname -eq "item_name" }
    $itemCodeField = $DocType.data.fields | Where-Object { $_.fieldname -eq "item_code" }
    
    Write-Host "`nCurrent configuration:" -ForegroundColor White
    Write-Host "  item_name.in_list_view: $($itemNameField.in_list_view)" -ForegroundColor Gray
    Write-Host "  item_code.in_list_view: $($itemCodeField.in_list_view)" -ForegroundColor Gray
    
    if ($itemNameField.in_list_view -eq 1 -and $itemCodeField.in_list_view -eq 0) {
        Write-Host "`nâœ“ Already configured correctly!" -ForegroundColor Green
    } else {
        Write-Host "`nâš  Needs configuration. Run with -Mode Deploy" -ForegroundColor Yellow
    }
}

