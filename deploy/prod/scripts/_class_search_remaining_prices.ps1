$ErrorActionPreference = "Stop"

$RemainingPath = "C:\Users\Levon\.windsurf\PERM_prices_still_missing.csv"
$PricePath = (Get-ChildItem "C:\Users\Levon\.windsurf" -Filter "Chunly*.xlsx" | Select-Object -First 1).FullName
$OutPath = "C:\Users\Levon\.windsurf\PERM_remaining_class_price_candidates.csv"

function Normalize([string]$s) {
    if ($null -eq $s) { return "" }
    $x = $s.ToLowerInvariant()
    $x = $x -replace '\r|\n', ' '
    $x = $x -replace '58liner', 'liner'
    $x = $x -replace '64 liner', 'liner'
    $x = $x -replace '64 cup', 'acetabular cup'
    $x = $x -replace 'cemented cup hxlpe', 'cemented cup'
    $x = $x -replace 'ceramic head', 'ceramic head'
    $x = $x -replace 'femoral head t', 'femoral head'
    $x = $x -replace 'femoral stem bc4', 'femoral stem'
    $x = $x -replace 'wagner femoral stem', 'wagner femoral stem'
    $x = $x -replace 'screw for tibial part', 'screw'
    $x = $x -replace '[^a-z0-9]+', ' '
    $x = $x -replace '\b(xs|s|m|l|xl|xxl|left|right|r|l)\b', ' '
    $x = $x -replace '\b\d+(\.\d+)?\b', ' '
    $x = $x -replace '\s+', ' '
    $x.Trim()
}

function Tokens([string]$s) {
    $stop = @('with','working','size','sizes','of','and','from','part','for','the','mm','head','cup')
    @(Normalize $s -split ' ' | Where-Object { $_ -and $_.Length -gt 1 -and $stop -notcontains $_ })
}

function Score($a, $b) {
    if ($a.Count -eq 0 -or $b.Count -eq 0) { return 0 }
    $common = @($a | Where-Object { $b -contains $_ })
    return [math]::Round($common.Count / [math]::Max($a.Count, 1), 4)
}

$remaining = Import-Csv $RemainingPath
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
        $desc = ($ws.Cells.Item($r,4).Text).Trim()
        $buyText = ($ws.Cells.Item($r,6).Text).Trim().Replace(',', '')
        $sellText = ($ws.Cells.Item($r,7).Text).Trim().Replace(',', '')
        if ($group) { $lastGroup = $group }
        $buy = 0.0; $sell = 0.0
        $hasBuy = [double]::TryParse($buyText, [ref]$buy)
        $hasSell = [double]::TryParse($sellText, [ref]$sell)
        if (($hasBuy -or $hasSell) -and ($ref -or $lastGroup -or $desc)) {
            $full = (($lastGroup, $desc) | Where-Object { $_ }) -join ' '
            $priced += [pscustomobject]@{ Ref=$ref; FullName=$full; Group=$lastGroup; Desc=$desc; BuyingUSD=$buy; SellingUSD=$sell; Sheet=$ws.Name; Row=$r; Tokens=(Tokens $full) }
        }
    }
}
$wb.Close($false)
$excel.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($wb) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null

Write-Host "Priced candidate rows loaded: $($priced.Count)"

$out = @()
foreach ($m in $remaining) {
    $mt = Tokens $m.ItemName
    $candidates = @()
    foreach ($p in $priced) {
        $sc = Score $mt $p.Tokens
        if ($sc -ge 0.34) {
            $candidates += [pscustomobject]@{ Score=$sc; Ref=$p.Ref; PriceName=$p.FullName; BuyingUSD=$p.BuyingUSD; SellingUSD=$p.SellingUSD; Sheet=$p.Sheet; Row=$p.Row }
        }
    }
    $top = @($candidates | Sort-Object @{Expression='Score';Descending=$true}, @{Expression='BuyingUSD';Descending=$false} | Select-Object -First 10)
    $strong = @($top | Where-Object { $_.Score -ge 0.5 })
    $rates = @($strong | Select-Object -ExpandProperty BuyingUSD -Unique)
    $suggestBuy = ""
    $suggestSell = ""
    $confidence = "No candidate"
    if ($strong.Count -gt 0 -and $rates.Count -eq 1) {
        $suggestBuy = $strong[0].BuyingUSD
        $suggestSell = $strong[0].SellingUSD
        $confidence = "Strong class match - same buying rate"
    } elseif ($strong.Count -gt 0) {
        $confidence = "Review - strong class matches multiple buying rates"
    } elseif ($top.Count -gt 0) {
        $confidence = "Weak candidates - review"
    }
    $out += [pscustomobject]@{
        ItemCode=$m.ItemCode
        ItemName=$m.ItemName
        Qty=$m.Qty
        SuggestedBuyingUSD=$suggestBuy
        SuggestedSellingUSD=$suggestSell
        Confidence=$confidence
        Candidates=(($top | ForEach-Object { "$($_.Ref) | $($_.PriceName) | buy=$($_.BuyingUSD) sell=$($_.SellingUSD) score=$($_.Score)" }) -join ' || ')
    }
}

$out | Export-Csv -Path $OutPath -NoTypeInformation -Encoding UTF8
Write-Host "Report written: $OutPath" -ForegroundColor Green
Write-Host "Strong suggestions: $(($out | Where-Object { $_.SuggestedBuyingUSD -ne '' }).Count) / $($out.Count)"
Write-Host "Needs review: $(($out | Where-Object { $_.SuggestedBuyingUSD -eq '' -and $_.Confidence -ne 'No candidate' }).Count)"
Write-Host "No candidates: $(($out | Where-Object { $_.Confidence -eq 'No candidate' }).Count)"
$out | Format-Table ItemCode, ItemName, SuggestedBuyingUSD, SuggestedSellingUSD, Confidence -AutoSize
