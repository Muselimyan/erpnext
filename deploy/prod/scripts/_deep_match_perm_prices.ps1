$ErrorActionPreference = "Stop"

$MissingPath = "C:\Users\Levon\.windsurf\PERM_prices_still_missing.csv"
$PricePath = (Get-ChildItem "C:\Users\Levon\.windsurf" -Filter "Chunly*.xlsx" | Select-Object -First 1).FullName
$OutPath = "C:\Users\Levon\.windsurf\PERM_deep_price_suggestions.csv"

function NormName([string]$s) {
    $x = $s.ToLowerInvariant()
    $x = $x -replace '\([^\)]*\)', ' '
    $x = $x -replace '#', ' '
    $x = $x -replace '[,;]+', ' '
    $x = $x -replace '[-–—_/]+', ' '
    $x = $x -replace '\b(xs|s|m|l|xl|xxl)\b', ' '
    $x = $x -replace '(\d)(xs|s|m|l|xl|xxl)\b', '$1 '
    $x = $x -replace '\b\d+(\.\d+)?\s*(mm)?\b', ' '
    $x = $x -replace '\s+', ' '
    $x.Trim()
}

function Tokens([string]$s) {
    @(NormName $s -split ' ' | Where-Object { $_ -and $_.Length -gt 1 -and $_ -notin @('with','working','size','head','cup') })
}

function Score($aTokens, $bTokens) {
    if ($aTokens.Count -eq 0 -or $bTokens.Count -eq 0) { return 0 }
    $common = @($aTokens | Where-Object { $bTokens -contains $_ })
    return [math]::Round((2.0 * $common.Count) / ($aTokens.Count + $bTokens.Count), 4)
}

$missing = Import-Csv $MissingPath

Write-Host "Reading price file: $PricePath"
$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$wb = $excel.Workbooks.Open($PricePath)

$priced = @()
for ($i=1; $i -le $wb.Worksheets.Count; $i++) {
    $ws = $wb.Worksheets.Item($i)
    $rows = $ws.UsedRange.Rows.Count
    $lastGroup = ""
    for ($r=1; $r -le $rows; $r++) {
        $ref = ($ws.Cells.Item($r,1).Text).Trim()
        $group = ($ws.Cells.Item($r,3).Text).Trim()
        $sizeDesc = ($ws.Cells.Item($r,4).Text).Trim()
        $buyText = ($ws.Cells.Item($r,6).Text).Trim().Replace(',', '')
        $sellText = ($ws.Cells.Item($r,7).Text).Trim().Replace(',', '')
        if ($group) { $lastGroup = $group }
        if ($ref -match '^[0-9A-Za-z][0-9A-Za-z\.\-]+$') {
            $buy = 0.0; $sell = 0.0
            $hasBuy = [double]::TryParse($buyText, [ref]$buy)
            $hasSell = [double]::TryParse($sellText, [ref]$sell)
            if ($hasBuy -or $hasSell) {
                $displayName = (($lastGroup, $sizeDesc) | Where-Object { $_ }) -join ' '
                $priced += [pscustomobject]@{
                    Ref=$ref; Name=$displayName; Group=$lastGroup; SizeDesc=$sizeDesc; BuyingUSD=$buy; SellingUSD=$sell; Sheet=$ws.Name; Row=$r; Tokens=(Tokens $displayName)
                }
            }
        }
    }
}
$wb.Close($false); $excel.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($wb) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null

Write-Host "Priced rows loaded: $($priced.Count)"

$suggestions = @()
foreach ($m in $missing) {
    $mt = Tokens $m.ItemName
    $candidates = @()
    foreach ($p in $priced) {
        $sc = Score $mt $p.Tokens
        if ($sc -ge 0.45) {
            $candidates += [pscustomobject]@{ Score=$sc; Ref=$p.Ref; Name=$p.Name; BuyingUSD=$p.BuyingUSD; SellingUSD=$p.SellingUSD; Sheet=$p.Sheet; Row=$p.Row }
        }
    }
    $top = @($candidates | Sort-Object @{Expression='Score';Descending=$true}, @{Expression='Ref';Descending=$false} | Select-Object -First 8)
    $rates = @($top | Where-Object { $_.Score -ge 0.55 } | Select-Object -ExpandProperty BuyingUSD -Unique)
    $suggested = ""
    $confidence = "No strong family match"
    if ($rates.Count -eq 1) {
        $suggested = $rates[0]
        $confidence = "Review - strong family matches agree"
    } elseif ($rates.Count -gt 1) {
        $confidence = "Manual review - multiple rates: " + (($rates | ForEach-Object { $_.ToString() }) -join ', ')
    } elseif ($top.Count -gt 0) {
        $confidence = "Weak match - review manually"
    }
    $suggestions += [pscustomobject]@{
        ItemCode=$m.ItemCode
        ItemName=$m.ItemName
        Qty=$m.Qty
        SuggestedBuyingUSD=$suggested
        Confidence=$confidence
        BestMatches=(($top | ForEach-Object { "$($_.Ref) | $($_.Name) | buy=$($_.BuyingUSD) | score=$($_.Score)" }) -join ' || ')
    }
}

$suggestions | Export-Csv -Path $OutPath -NoTypeInformation -Encoding UTF8
Write-Host "Report written: $OutPath" -ForegroundColor Green
Write-Host "Suggestions with price: $(($suggestions | Where-Object { $_.SuggestedBuyingUSD -ne '' }).Count) / $($suggestions.Count)"
$suggestions | Format-Table ItemCode, ItemName, SuggestedBuyingUSD, Confidence -AutoSize
