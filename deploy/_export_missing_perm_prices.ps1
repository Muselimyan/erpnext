$ErrorActionPreference = "Stop"

$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

$ExcelPath = "C:\Users\Levon\.windsurf\PERM.xlsx"
$OutPath = "C:\Users\Levon\.windsurf\PERM_missing_buying_prices.csv"

function Enc([string]$s) { [uri]::EscapeDataString($s) }
function Get-Api($Path) { Invoke-RestMethod -Uri "$BaseUrl$Path" -Headers $Headers -Method Get -TimeoutSec 20 }

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

$missing = @()
$idx = 0
foreach ($it in $items) {
    $idx++
    if ($idx % 50 -eq 0) { Write-Host "Checked $idx / $($items.Count)..." }

    $filterItem = Enc "[[`"Item`",`"item_code`",`"=`",`"$($it.ItemCode)`"]]"
    $itemPath = "/api/resource/Item?fields=[`"name`",`"item_code`",`"item_name`",`"last_purchase_rate`",`"valuation_rate`",`"has_batch_no`",`"has_expiry_date`"]&filters=$filterItem&limit_page_length=1"
    $itemRows = @()
    try { $itemRows = (Get-Api $itemPath).data } catch { }
    if ($itemRows.Count -eq 0) {
        $missing += [pscustomobject]@{ Row=$it.Row; ItemCode=$it.ItemCode; ItemName=$it.ItemName; Qty=$it.Qty; Reason="Item not found"; LastPurchaseRate=""; ValuationRate=""; HasBatchNo=""; HasExpiryDate="" }
        continue
    }
    $item = $itemRows[0]

    $filterBuy = Enc "[[`"Item Price`",`"item_code`",`"=`",`"$($it.ItemCode)`"],[`"Item Price`",`"buying`",`"=`",1]]"
    $pricePathBuy = "/api/resource/Item%20Price?fields=[`"name`",`"price_list`",`"price_list_rate`",`"currency`"]&filters=$filterBuy&limit_page_length=5"
    $buyPrices = @()
    try { $buyPrices = (Get-Api $pricePathBuy).data } catch { }
    if ($buyPrices.Count -eq 0) {
        $missing += [pscustomobject]@{
            Row=$it.Row
            ItemCode=$it.ItemCode
            ItemName=$it.ItemName
            Qty=$it.Qty
            Reason="Missing buying Item Price"
            LastPurchaseRate=$item.last_purchase_rate
            ValuationRate=$item.valuation_rate
            HasBatchNo=$item.has_batch_no
            HasExpiryDate=$item.has_expiry_date
        }
    }
}

$missing | Export-Csv -Path $OutPath -NoTypeInformation -Encoding UTF8
Write-Host ""
Write-Host "Missing buying price rows: $($missing.Count)" -ForegroundColor Yellow
Write-Host "Report written: $OutPath" -ForegroundColor Green
Write-Host ""
$missing | Select-Object -First 30 | Format-Table -AutoSize
