$ErrorActionPreference = "Stop"

$MissingPath = "C:\Users\Levon\.windsurf\PERM_missing_buying_prices.csv"
$PricePath = (Get-ChildItem "C:\Users\Levon\.windsurf" -Filter "Chunly*.xlsx" | Select-Object -First 1).FullName
$OutPath = "C:\Users\Levon\.windsurf\PERM_missing_prices_matched_from_chunly.csv"

Write-Host "Missing list: $MissingPath"
Write-Host "Price file: $PricePath"

$missing = Import-Csv $MissingPath

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$wb = $excel.Workbooks.Open($PricePath)

$priceMap = @{}
for ($i=1; $i -le $wb.Worksheets.Count; $i++) {
    $ws = $wb.Worksheets.Item($i)
    $rows = $ws.UsedRange.Rows.Count
    for ($r=1; $r -le $rows; $r++) {
        $ref = ($ws.Cells.Item($r,1).Text).Trim()
        if ($ref -match '^[0-9A-Za-z][0-9A-Za-z\.\-]+$') {
            $buyText = ($ws.Cells.Item($r,6).Text).Trim().Replace(',', '')
            $sellText = ($ws.Cells.Item($r,7).Text).Trim().Replace(',', '')
            $buy = $null
            $sell = $null
            $tmp = 0.0
            if ([double]::TryParse($buyText, [ref]$tmp)) { $buy = $tmp }
            $tmp = 0.0
            if ([double]::TryParse($sellText, [ref]$tmp)) { $sell = $tmp }
            if ($buy -ne $null -or $sell -ne $null) {
                $priceMap[$ref] = [pscustomobject]@{ Sheet=$ws.Name; Row=$r; BuyingUSD=$buy; SellingUSD=$sell }
            }
        }
    }
}
$wb.Close($false)
$excel.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($wb) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null

$rows = @()
foreach ($m in $missing) {
    $p = $priceMap[$m.ItemCode]
    if ($p) {
        $status = if ($p.BuyingUSD -ne $null) { "Matched buying" } else { "Matched selling only" }
        $rows += [pscustomobject]@{ ItemCode=$m.ItemCode; ItemName=$m.ItemName; Qty=$m.Qty; MatchStatus=$status; BuyingUSD=$p.BuyingUSD; SellingUSD=$p.SellingUSD; PriceSheet=$p.Sheet; PriceRow=$p.Row }
    } else {
        $rows += [pscustomobject]@{ ItemCode=$m.ItemCode; ItemName=$m.ItemName; Qty=$m.Qty; MatchStatus="Not found in price file"; BuyingUSD=""; SellingUSD=""; PriceSheet=""; PriceRow="" }
    }
}

$rows | Export-Csv -Path $OutPath -NoTypeInformation -Encoding UTF8
Write-Host ""
Write-Host "Price refs loaded: $($priceMap.Count)"
Write-Host "Missing-price items checked: $($missing.Count)"
Write-Host "Matched buying: $(($rows | Where-Object { $_.MatchStatus -eq 'Matched buying' }).Count)" -ForegroundColor Green
Write-Host "Matched selling only: $(($rows | Where-Object { $_.MatchStatus -eq 'Matched selling only' }).Count)" -ForegroundColor Yellow
Write-Host "Still not found: $(($rows | Where-Object { $_.MatchStatus -eq 'Not found in price file' }).Count)" -ForegroundColor Red
Write-Host "Report written: $OutPath" -ForegroundColor Green
Write-Host ""
$rows | Select-Object -First 40 | Format-Table -AutoSize
