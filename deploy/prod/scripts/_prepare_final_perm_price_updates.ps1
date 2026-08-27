$ErrorActionPreference = "Stop"

$ExactPath = "C:\Users\Levon\.windsurf\PERM_buying_prices_to_create.csv"
$RemainingPath = "C:\Users\Levon\.windsurf\PERM_prices_still_missing.csv"
$OutPath = "C:\Users\Levon\.windsurf\PERM_final_prices_to_create.csv"
$ApplyPath = "C:\Users\Levon\Windsurf\erpnext\deploy\_apply_final_perm_prices.ps1"

$exact = Import-Csv $ExactPath
$remaining = Import-Csv $RemainingPath
$manual = @{}

function Add-Manual($code, $buy, $sell, $source) {
    $manual[$code] = [pscustomobject]@{ BuyingUSD=$buy; SellingUSD=$sell; Source=$source }
}

# 58Liner-PE / Liner-HXLPE
@('3150-28353.1','3150-28373.1','3150-32393.1','3150-36443.1','3150-36483.1','3150-36523.1') | ForEach-Object { Add-Manual $_ 83 148 'Liner-HXLPE rows 79-84' }
# 64 Cup - Dual Mobility Cup
@('3154-05460','3154-05480','3154-05500','3154-05520','3154-05540','3154-05560','3154-05580','3154-05600','3154-05620','3154-05640') | ForEach-Object { Add-Manual $_ 308 558 '64 Cup - Dual Mobility Cup row 148' }
# 64 Liner Dual mobility
@('3154-22461','3154-22481','3154-22501','3154-22541','3154-22581','3154-22621') | ForEach-Object { Add-Manual $_ 1 2 '64 Liner Dual mobility row 159' }
Add-Manual '3170-28600' 88 167 'Cemented Cup-HXLPE row 166'
Add-Manual '3211-02260' 270 495 'Ceramic Head 36XL row 122'
@('5126-30021','5126-30022') | ForEach-Object { Add-Manual $_ 308 920 'Femoral Cone rows 199-200' }
Add-Manual '3210-16360' 50 92 'Femoral Head-T 36/6 row 110'
@('3514-02100','3514-02110','3514-02120','3514-02130','3514-02140','3514-02090') | ForEach-Object { Add-Manual $_ 121 320 'BC4 Stem row 47' }
@('5279-00600','5279-00700') | ForEach-Object { Add-Manual $_ 16.5 45 'Screws for tibia/femoral part rows 194-195' }
@('5271-17031','5271-19031','5271-11051','5271-13051','5271-15051','5271-09051') | ForEach-Object { Add-Manual $_ 121 363 'Tibial Insert-XN(R-CCK) row 62' }
@('3205-10044','3205-12044','3205-13044','3205-15044','3205-16044','3250-10044','3250-11044','3250-12044','3250-13044','3250-14044','3250-15044','3250-16044') | ForEach-Object { Add-Manual $_ 171 600 'Wagner Type Stem rows 31/39' }

$final = @()
foreach ($r in $exact) {
    $final += [pscustomobject]@{ ItemCode=$r.ItemCode; ItemName=$r.ItemName; BuyingUSD=$r.BuyingUSD; SellingUSD=$r.SellingUSD; Source='Exact REF match from Chunly price file' }
}
foreach ($r in $remaining) {
    if ($manual.ContainsKey($r.ItemCode)) {
        $m = $manual[$r.ItemCode]
        $final += [pscustomobject]@{ ItemCode=$r.ItemCode; ItemName=$r.ItemName; BuyingUSD=$m.BuyingUSD; SellingUSD=$m.SellingUSD; Source=$m.Source }
    }
}

$final = @($final | Sort-Object ItemCode -Unique)
$final | Export-Csv -Path $OutPath -NoTypeInformation -Encoding UTF8

$apply = @'
$ErrorActionPreference = "Stop"

$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
$Rows = Import-Csv "C:\Users\Levon\.windsurf\PERM_final_prices_to_create.csv"

function Enc([string]$s) { [uri]::EscapeDataString($s) }
function Get-ExistingPrice($itemCode, $priceList, $buying, $selling) {
    $filters = Enc "[[`"Item Price`",`"item_code`",`"=`",`"$itemCode`"],[`"Item Price`",`"price_list`",`"=`",`"$priceList`"],[`"Item Price`",`"buying`",`"=`",$buying],[`"Item Price`",`"selling`",`"=`",$selling]]"
    $uri = "$BaseUrl/api/resource/Item%20Price?fields=[`"name`"]&filters=$filters&limit_page_length=1"
    try { return (Invoke-RestMethod -Uri $uri -Headers $Headers -Method Get -TimeoutSec 20).data } catch { return @() }
}
function Create-Price($itemCode, $priceList, $rate, $buying, $selling) {
    $existing = @(Get-ExistingPrice $itemCode $priceList $buying $selling)
    if ($existing.Count -gt 0) {
        Write-Host "Skip existing: $itemCode / $priceList"
        return
    }
    $bodyObj = @{ item_code=$itemCode; price_list=$priceList; price_list_rate=[decimal]$rate; currency='USD'; buying=$buying; selling=$selling }
    $body = $bodyObj | ConvertTo-Json -Depth 5 -Compress
    Write-Host "Create: $itemCode / $priceList = $rate USD"
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Item%20Price" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
}

Write-Host "Rows: $($Rows.Count)"
foreach ($r in $Rows) {
    if ($r.BuyingUSD -and [decimal]$r.BuyingUSD -gt 0) { Create-Price $r.ItemCode 'Standard Buying' $r.BuyingUSD 1 0 }
    if ($r.SellingUSD -and [decimal]$r.SellingUSD -gt 0) { Create-Price $r.ItemCode 'Standard Selling' $r.SellingUSD 0 1 }
}
Write-Host "Done." -ForegroundColor Green
'@
Set-Content -Path $ApplyPath -Value $apply -Encoding UTF8

$expectedCodes = @($exact.ItemCode + $remaining.ItemCode | Select-Object -Unique)
$covered = @($final.ItemCode | Select-Object -Unique)
$uncovered = @($expectedCodes | Where-Object { $covered -notcontains $_ })

Write-Host "Final price rows prepared: $($final.Count)" -ForegroundColor Green
Write-Host "Uncovered missing-price item codes: $($uncovered.Count)" -ForegroundColor Yellow
Write-Host "Review file: $OutPath"
Write-Host "Apply script created, DO NOT RUN until confirmed: $ApplyPath" -ForegroundColor Cyan
if ($uncovered.Count -gt 0) { $uncovered | ForEach-Object { Write-Host "Uncovered: $_" } }
Write-Host ""
$final | Select-Object -First 40 | Format-Table -AutoSize
