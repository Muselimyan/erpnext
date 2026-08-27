$ErrorActionPreference = "Stop"

$MatchedPath = "C:\Users\Levon\.windsurf\PERM_missing_prices_matched_from_chunly.csv"
$ToCreatePath = "C:\Users\Levon\.windsurf\PERM_buying_prices_to_create.csv"
$StillMissingPath = "C:\Users\Levon\.windsurf\PERM_prices_still_missing.csv"
$DeployPath = "C:\Users\Levon\Windsurf\erpnext\deploy\_apply_perm_buying_prices.ps1"

$rows = Import-Csv $MatchedPath
$toCreate = @($rows | Where-Object { $_.MatchStatus -eq "Matched buying" -and $_.BuyingUSD -ne "" })
$stillMissing = @($rows | Where-Object { $_.MatchStatus -ne "Matched buying" })

$toCreate | Export-Csv -Path $ToCreatePath -NoTypeInformation -Encoding UTF8
$stillMissing | Export-Csv -Path $StillMissingPath -NoTypeInformation -Encoding UTF8

$script = @'
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
'@

Set-Content -Path $DeployPath -Value $script -Encoding UTF8

Write-Host "Buying prices to create: $($toCreate.Count)" -ForegroundColor Green
Write-Host "Still missing prices: $($stillMissing.Count)" -ForegroundColor Yellow
Write-Host "Created review file: $ToCreatePath"
Write-Host "Created remaining missing file: $StillMissingPath"
Write-Host "Created apply script, DO NOT RUN until reviewed: $DeployPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "Remaining missing sample:"
$stillMissing | Select-Object -First 30 | Format-Table -AutoSize
