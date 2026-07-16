$ErrorActionPreference = "Stop"

$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
$ExcelPath = "C:\Users\Levon\.windsurf\PERM.xlsx"
$OutPath = "C:\Users\Levon\.windsurf\PERM_price_family_suggestions.csv"

function Enc([string]$s) { [uri]::EscapeDataString($s) }
function Get-Api($Path) { Invoke-RestMethod -Uri "$BaseUrl$Path" -Headers $Headers -Method Get -TimeoutSec 20 }
function FamilyKey([string]$name) {
    $x = $name.ToLowerInvariant()
    $x = [regex]::Replace($x, '\([^\)]*\)', '')
    $x = [regex]::Replace($x, '#', '')
    $x = [regex]::Replace($x, '\b\d+(\.\d+)?\b', '')
    $x = [regex]::Replace($x, '\b\d+\/\d+\b', '')
    $x = [regex]::Replace($x, '[-–—_/]+', ' ')
    $x = [regex]::Replace($x, '\s+', ' ').Trim()
    return $x
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
    if ($code) {
        $qty = 0; [decimal]::TryParse($qtyText, [ref]$qty) | Out-Null
        $items += [pscustomobject]@{ Row=$r; ItemCode=$code; ItemName=$name; Qty=$qty; Family=(FamilyKey $name) }
    }
}
$wb.Close($false); $excel.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($ws) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($wb) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null

$priced = @()
$missing = @()
$idx = 0
foreach ($it in $items) {
    $idx++; if ($idx % 50 -eq 0) { Write-Host "Checked $idx / $($items.Count)..." }
    $filterBuy = Enc "[[`"Item Price`",`"item_code`",`"=`",`"$($it.ItemCode)`"],[`"Item Price`",`"buying`",`"=`",1]]"
    $path = "/api/resource/Item%20Price?fields=[`"name`",`"price_list`",`"price_list_rate`",`"currency`"]&filters=$filterBuy&limit_page_length=5"
    $buy = @(); try { $buy = (Get-Api $path).data } catch { }
    if ($buy.Count -gt 0) {
        $priced += [pscustomobject]@{ Row=$it.Row; ItemCode=$it.ItemCode; ItemName=$it.ItemName; Qty=$it.Qty; Family=$it.Family; BuyRate=[decimal]$buy[0].price_list_rate; PriceList=$buy[0].price_list; Currency=$buy[0].currency }
    } else {
        $missing += $it
    }
}

$suggestions = @()
foreach ($m in $missing) {
    $same = @($priced | Where-Object { $_.Family -eq $m.Family })
    $rates = @($same | Select-Object -ExpandProperty BuyRate -Unique)
    $suggested = ""
    $confidence = "No family priced match"
    $examples = ""
    if ($same.Count -gt 0 -and $rates.Count -eq 1) {
        $suggested = $rates[0]
        $confidence = "High - same normalized family has one buying rate"
        $examples = (($same | Select-Object -First 5 | ForEach-Object { "$($_.ItemCode):$($_.BuyRate)" }) -join "; ")
    } elseif ($same.Count -gt 0) {
        $confidence = "Review - same normalized family has multiple rates: " + (($rates | ForEach-Object { $_.ToString() }) -join ", ")
        $examples = (($same | Select-Object -First 8 | ForEach-Object { "$($_.ItemCode):$($_.BuyRate)" }) -join "; ")
    }
    $suggestions += [pscustomobject]@{ Row=$m.Row; ItemCode=$m.ItemCode; ItemName=$m.ItemName; Qty=$m.Qty; Family=$m.Family; SuggestedBuyingRate=$suggested; Confidence=$confidence; PricedExamples=$examples }
}

$suggestions | Export-Csv -Path $OutPath -NoTypeInformation -Encoding UTF8
Write-Host ""
Write-Host "Priced rows: $($priced.Count)"
Write-Host "Missing rows: $($missing.Count)"
Write-Host "High-confidence suggestions: $(($suggestions | Where-Object { $_.SuggestedBuyingRate -ne '' }).Count)"
Write-Host "Report written: $OutPath" -ForegroundColor Green
Write-Host ""
$suggestions | Select-Object -First 40 | Format-Table Row, ItemCode, ItemName, SuggestedBuyingRate, Confidence -AutoSize
