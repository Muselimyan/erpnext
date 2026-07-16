$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
$Items = Import-Csv "C:\Users\Levon\.windsurf\PERM_quantity_items.csv"
function Enc([string]$s) { [uri]::EscapeDataString($s) }
Write-Host "Disabling Has Batch No / Has Expiry Date for PERM items: $($Items.Count)"
$idx = 0
foreach ($it in $Items) {
    $idx++
    if ($idx % 50 -eq 0) { Write-Host "Updated $idx / $($Items.Count)..." }
    $body = '{"has_batch_no":0,"has_expiry_date":0}'
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Item/$(Enc $it.ItemCode)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
}
Write-Host "Done disabling tracking flags." -ForegroundColor Green
