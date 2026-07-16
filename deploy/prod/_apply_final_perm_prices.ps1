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
