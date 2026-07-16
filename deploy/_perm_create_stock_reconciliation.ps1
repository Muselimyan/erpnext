$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
$Items = Import-Csv "C:\Users\Levon\.windsurf\PERM_quantity_items.csv"
$Warehouse = "Main - Inmed"
$Purpose = "Stock Reconciliation"
$Company = "Inmed"
$today = (Get-Date).ToString("yyyy-MM-dd")
$srItems = @()
foreach ($it in $Items) {
    if ([decimal]$it.Qty -gt 0) {
        $srItems += @{ item_code=$it.ItemCode; warehouse=$Warehouse; qty=[decimal]$it.Qty; valuation_rate=[decimal]$it.ValuationRate }
    }
}
$doc = @{ doctype="Stock Reconciliation"; purpose=$Purpose; company=$Company; posting_date=$today; posting_time=(Get-Date).ToString("HH:mm:ss"); set_posting_time=1; items=$srItems }
$body = $doc | ConvertTo-Json -Depth 8 -Compress
Write-Host "Creating Stock Reconciliation with item rows: $($srItems.Count)"
$r = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Stock%20Reconciliation" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 120
$name = $r.data.name
Write-Host "Created draft Stock Reconciliation: $name" -ForegroundColor Green
Write-Host "Submitting Stock Reconciliation: $name"
$submitBody = '{"docstatus":1}'
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Stock%20Reconciliation/$name" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($submitBody)) -TimeoutSec 120 | Out-Null
Write-Host "Submitted Stock Reconciliation: $name" -ForegroundColor Green
