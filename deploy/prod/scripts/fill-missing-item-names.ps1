param(
    [string]$DispatchCaseName
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

Write-Host "=== Fill Missing Item Names in Dispatch Case Items ===" -ForegroundColor Cyan

if ($DispatchCaseName) {
    Write-Host "`nProcessing Dispatch Case: $DispatchCaseName" -ForegroundColor Yellow
    
    # Get the Dispatch Case
    $DispatchCase = Invoke-ErpRequest -Method Get -Path "/api/resource/Dispatch Case/$(Enc $DispatchCaseName)"
    
    $updated = 0
    foreach ($item in $DispatchCase.data.case_items) {
        if ($item.item_code -and -not $item.item_name) {
            Write-Host "  Item Code: $($item.item_code) - fetching name..." -ForegroundColor Gray
            
            # Get Item Name from Item master
            try {
                $ItemDoc = Invoke-ErpRequest -Method Get -Path "/api/resource/Item/$(Enc $item.item_code)?fields=[%22item_name%22]"
                $item.item_name = $ItemDoc.data.item_name
                Write-Host "    → $($ItemDoc.data.item_name)" -ForegroundColor Green
                $updated++
            }
            catch {
                Write-Host "    → Could not fetch name" -ForegroundColor Red
            }
        }
    }
    
    if ($updated -gt 0) {
        Write-Host "`nSaving Dispatch Case with updated Item Names..." -ForegroundColor Yellow
        $Result = Invoke-ErpRequest -Method Put -Path "/api/resource/Dispatch Case/$(Enc $DispatchCaseName)" -Body $DispatchCase.data
        Write-Host "Done! Updated $updated items." -ForegroundColor Green
    }
    else {
        Write-Host "`nNo items needed updating." -ForegroundColor Gray
    }
}
else {
    Write-Host "`nUsage: .\fill-missing-item-names.ps1 -DispatchCaseName 'DC-00123'" -ForegroundColor Yellow
    Write-Host "This will fill missing Item Names for all items in the specified Dispatch Case." -ForegroundColor White
}
