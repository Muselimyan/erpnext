$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)" }
$fields = [uri]::EscapeDataString('["name","warehouse_name","company","is_group"]')
$filters = [uri]::EscapeDataString('[["Warehouse","company","=","Inmed"]]')
$r = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Warehouse?fields=$fields&filters=$filters&limit_page_length=200" -Headers $Headers -Method Get -TimeoutSec 30
$r.data | Sort-Object name | Format-Table -AutoSize
