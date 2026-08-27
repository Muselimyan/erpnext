$ErrorActionPreference = "Stop"

$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

$ExcelPath = "C:\Users\Levon\.windsurf\PERM.xlsx"
$Warehouse = "Պահեստ Հիմնական - Inmed"
$OutItems = "C:\Users\Levon\.windsurf\PERM_quantity_items.csv"
$DisableScript = "C:\Users\Levon\Windsurf\erpnext\deploy\_perm_disable_batch_expiry.ps1"
$ReconcileScript = "C:\Users\Levon\Windsurf\erpnext\deploy\_perm_create_stock_reconciliation.ps1"

function Enc([string]$s) { [uri]::EscapeDataString($s) }
function Get-Api($Path) { Invoke-RestMethod -Uri "$BaseUrl$Path" -Headers $Headers -Method Get -TimeoutSec 20 }

Write-Host "Reading Excel quantities: $ExcelPath"
$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$wb = $excel.Workbooks.Open($ExcelPath)
$ws = $wb.Worksheets.Item(1)
$rows = $ws.UsedRange.Rows.Count
$items = @()
for ($r = 9; $r -le $rows; $r++) {
    $code = ($ws.Cells.Item($r,4).Text).Trim()
    $name = ($ws.Cells.Item($r,5).Text).Trim()
    $qtyText = ($ws.Cells.Item($r,9).Text).Trim().Replace(',', '')
    if ($code) {
        $qty = 0
        [decimal]::TryParse($qtyText, [ref]$qty) | Out-Null
        $items += [pscustomobject]@{ Row=$r; ItemCode=$code; ItemName=$name; Warehouse=$Warehouse; Qty=$qty; ValuationRate=0; HasBatchNo=""; HasExpiryDate="" }
    }
}
$wb.Close($false)
$excel.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($ws) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($wb) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null

Write-Host "Loaded rows: $($items.Count). Fetching Standard Buying rates and item tracking flags..."
$idx = 0
foreach ($it in $items) {
    $idx++
    if ($idx % 50 -eq 0) { Write-Host "Prepared $idx / $($items.Count)..." }
    $filterItem = Enc "[[`"Item`",`"item_code`",`"=`",`"$($it.ItemCode)`"]]"
    $itemRows = (Get-Api "/api/resource/Item?fields=[`"name`",`"has_batch_no`",`"has_expiry_date`"]&filters=$filterItem&limit_page_length=1").data
    if ($itemRows.Count -eq 0) { throw "Item not found: $($it.ItemCode)" }
    $it.HasBatchNo = $itemRows[0].has_batch_no
    $it.HasExpiryDate = $itemRows[0].has_expiry_date

    $filterPrice = Enc "[[`"Item Price`",`"item_code`",`"=`",`"$($it.ItemCode)`"],[`"Item Price`",`"price_list`",`"=`",`"Standard Buying`"],[`"Item Price`",`"buying`",`"=`",1]]"
    $priceRows = (Get-Api "/api/resource/Item%20Price?fields=[`"price_list_rate`"]&filters=$filterPrice&limit_page_length=1").data
    if ($priceRows.Count -eq 0) { throw "Missing Standard Buying price after update: $($it.ItemCode)" }
    $it.ValuationRate = [decimal]$priceRows[0].price_list_rate
}

$items | Export-Csv -Path $OutItems -NoTypeInformation -Encoding UTF8

$disable = @'
$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
$Items = Import-Csv "C:\Users\Levon\.windsurf\PERM_quantity_items.csv"
function Enc([string]$s) { [uri]::EscapeDataString($s) }
Write-Host "Disabling Has Batch No / Has Expiry Date for PERM items: $($Items.Count)"
$idx = 0
foreach ($it in $Items) {
    $idx++
    if ($idx % 50 -eq 0) { Write-Host "Updated $idx / $($Items.Count)..." }
    $body = '{"has_batch_no":0,"has_expiry_date":0}'
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Item/$(Enc $it.ItemCode)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
}
Write-Host "Done disabling tracking flags." -ForegroundColor Green
'@
Set-Content -Path $DisableScript -Value $disable -Encoding UTF8

$reconcile = @'
$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
$Items = Import-Csv "C:\Users\Levon\.windsurf\PERM_quantity_items.csv"
$Warehouse = "Պահեստ Հիմնական - Inmed"
$Purpose = "Stock Reconciliation"
$Company = "Inmed"
$today = (Get-Date).ToString("yyyy-MM-dd")
$srItems = @()
foreach ($it in $Items) {
    if ([decimal]$it.Qty -gt 0) {
        $srItems += @{ item_code=$it.ItemCode; warehouse=$Warehouse; qty=[decimal]$it.Qty; valuation_rate=[decimal]$it.ValuationRate }
    }
}
$doc = @{ doctype="Stock Reconciliation"; purpose=$Purpose; company=$Company; posting_date=$today; posting_time=(Get-Date).ToString("HH:mm:ss"); set_posting_time=1; items=$srItems }
$body = $doc | ConvertTo-Json -Depth 8 -Compress
Write-Host "Creating Stock Reconciliation with item rows: $($srItems.Count)"
$r = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Stock%20Reconciliation" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 120
$name = $r.data.name
Write-Host "Created draft Stock Reconciliation: $name" -ForegroundColor Green
Write-Host "Submitting Stock Reconciliation: $name"
$submitBody = '{"docstatus":1}'
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Stock%20Reconciliation/$name" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($submitBody)) -TimeoutSec 120 | Out-Null
Write-Host "Submitted Stock Reconciliation: $name" -ForegroundColor Green
'@
Set-Content -Path $ReconcileScript -Value $reconcile -Encoding UTF8

Write-Host "Prepared quantity rows: $($items.Count)" -ForegroundColor Green
Write-Host "Rows with batch flag currently on: $(($items | Where-Object { $_.HasBatchNo -eq 1 }).Count)"
Write-Host "Rows with expiry flag currently on: $(($items | Where-Object { $_.HasExpiryDate -eq 1 }).Count)"
Write-Host "Quantity/rate file: $OutItems"
Write-Host "Disable script: $DisableScript"
Write-Host "Stock reconciliation script: $ReconcileScript"
Write-Host ""
$items | Select-Object -First 20 | Format-Table -AutoSize
