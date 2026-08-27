$ErrorActionPreference = "Stop"

$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

$ExcelPath = "C:\Users\Levon\.windsurf\PERM.xlsx"
$Warehouse = "Պահեստ Հիմնական - Inmed"

function Enc([string]$s) { [uri]::EscapeDataString($s) }
function Get-Api($Path) {
    return Invoke-RestMethod -Uri "$BaseUrl$Path" -Headers $Headers -Method Get -TimeoutSec 20
}

Write-Host "Reading Excel: $ExcelPath"
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
    if (-not [string]::IsNullOrWhiteSpace($code)) {
        $qty = 0
        [decimal]::TryParse($qtyText, [ref]$qty) | Out-Null
        $items += [pscustomobject]@{ Row=$r; ItemCode=$code; ItemName=$name; Qty=$qty }
    }
}
$wb.Close($false)
$excel.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($ws) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($wb) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null

Write-Host "Excel item rows: $($items.Count)"
Write-Host "Warehouse to use later: $Warehouse"
Write-Host "Checking ERPNext items and Item Price records..."

$total = $items.Count
$itemExists = 0
$buyFound = 0
$sellFound = 0
$missingItem = @()
$missingBuy = @()
$withBuy = @()

$idx = 0
foreach ($it in $items) {
    $idx++
    if ($idx % 50 -eq 0) { Write-Host "Checked $idx / $total..." }

    $filterItem = Enc "[[`"Item`",`"item_code`",`"=`",`"$($it.ItemCode)`"]]"
    $itemPath = "/api/resource/Item?fields=[`"name`",`"item_code`",`"item_name`",`"last_purchase_rate`",`"valuation_rate`",`"has_batch_no`",`"has_expiry_date`"]&filters=$filterItem&limit_page_length=1"
    $itemRows = @()
    try { $itemRows = (Get-Api $itemPath).data } catch { }
    if ($itemRows.Count -eq 0) {
        $missingItem += $it
        continue
    }
    $item = $itemRows[0]
    $itemExists++

    $filterBuy = Enc "[[`"Item Price`",`"item_code`",`"=`",`"$($it.ItemCode)`"],[`"Item Price`",`"buying`",`"=`",1]]"
    $pricePathBuy = "/api/resource/Item%20Price?fields=[`"name`",`"price_list`",`"price_list_rate`",`"currency`"]&filters=$filterBuy&limit_page_length=5"
    $buyPrices = @()
    try { $buyPrices = (Get-Api $pricePathBuy).data } catch { }

    $filterSell = Enc "[[`"Item Price`",`"item_code`",`"=`",`"$($it.ItemCode)`"],[`"Item Price`",`"selling`",`"=`",1]]"
    $pricePathSell = "/api/resource/Item%20Price?fields=[`"name`",`"price_list`",`"price_list_rate`",`"currency`"]&filters=$filterSell&limit_page_length=5"
    $sellPrices = @()
    try { $sellPrices = (Get-Api $pricePathSell).data } catch { }

    if ($buyPrices.Count -gt 0) {
        $buyFound++
        $withBuy += [pscustomobject]@{ ItemCode=$it.ItemCode; Qty=$it.Qty; BuyRate=$buyPrices[0].price_list_rate; BuyPriceList=$buyPrices[0].price_list; LastPurchaseRate=$item.last_purchase_rate; ValuationRate=$item.valuation_rate; Batch=$item.has_batch_no; Expiry=$item.has_expiry_date }
    } else {
        $missingBuy += [pscustomobject]@{ ItemCode=$it.ItemCode; ItemName=$it.ItemName; Qty=$it.Qty; LastPurchaseRate=$item.last_purchase_rate; ValuationRate=$item.valuation_rate; Batch=$item.has_batch_no; Expiry=$item.has_expiry_date }
    }
    if ($sellPrices.Count -gt 0) { $sellFound++ }
}

Write-Host ""
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "Excel rows/items: $total"
Write-Host "ERPNext Item matched: $itemExists"
Write-Host "Missing Item records: $($missingItem.Count)"
Write-Host "Buying Item Price found: $buyFound"
Write-Host "Selling Item Price found: $sellFound"
Write-Host "Missing Buying Item Price: $($missingBuy.Count)"

Write-Host ""
Write-Host "Sample rows WITH buying price:" -ForegroundColor Green
$withBuy | Select-Object -First 10 | Format-Table -AutoSize

Write-Host ""
Write-Host "Sample rows MISSING buying price:" -ForegroundColor Yellow
$missingBuy | Select-Object -First 15 | Format-Table -AutoSize

Write-Host ""
Write-Host "Sample missing Item records:" -ForegroundColor Red
$missingItem | Select-Object -First 15 | Format-Table -AutoSize
