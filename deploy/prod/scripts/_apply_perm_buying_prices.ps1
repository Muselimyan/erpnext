$ErrorActionPreference = "Stop"

$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

$Rows = Import-Csv "C:\Users\Levon\.windsurf\PERM_buying_prices_to_create.csv"
Write-Host "Will create buying Item Price rows: $($Rows.Count)"
Write-Host "Target price list: Standard Buying"
Write-Host "Currency: USD"

foreach ($r in $Rows) {
    $bodyObj = @{
        item_code = $r.ItemCode
        price_list = "Standard Buying"
        buying = 1
        selling = 0
        price_list_rate = [decimal]$r.BuyingUSD
        currency = "USD"
    }
    $body = $bodyObj | ConvertTo-Json -Depth 5 -Compress
    Write-Host "Creating buying price: $($r.ItemCode) = $($r.BuyingUSD) USD"
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Item%20Price" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
}

Write-Host "Done." -ForegroundColor Green
