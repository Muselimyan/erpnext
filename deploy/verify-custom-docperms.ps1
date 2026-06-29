Set-StrictMode -Off

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config     = Get-Content $ConfigPath -Raw
$BaseUrl    = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey     = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec     = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers    = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

function Enc ([string]$s) { [uri]::EscapeDataString($s) }

Write-Host "`n=== Verifying Custom DocPerms for Task ===" -ForegroundColor Cyan

$uri = "$BaseUrl/api/resource/Custom DocPerm?filters=[[`"parent`",`"=`",`"Task`"]]&fields=[`"role`",`"read`",`"write`",`"create`",`"delete`"]&limit_page_length=20"
$result = Invoke-RestMethod -Uri $uri -Headers $Headers -Method Get

if ($result.data -and $result.data.Count -gt 0) {
    Write-Host "`nFound $($result.data.Count) Custom DocPerms for Task:" -ForegroundColor Green
    $result.data | Format-Table -Property role, read, write, create, delete -AutoSize
} else {
    Write-Host "No Custom DocPerms found for Task!" -ForegroundColor Red
}

Write-Host "`n=== Verifying Custom DocPerms for Customer ===" -ForegroundColor Cyan

$uri = "$BaseUrl/api/resource/Custom DocPerm?filters=[[`"parent`",`"=`",`"Customer`"]]&fields=[`"role`",`"read`"]&limit_page_length=20"
$result = Invoke-RestMethod -Uri $uri -Headers $Headers -Method Get

if ($result.data -and $result.data.Count -gt 0) {
    Write-Host "`nFound $($result.data.Count) Custom DocPerms for Customer:" -ForegroundColor Green
    $result.data | Format-Table -Property role, read -AutoSize
} else {
    Write-Host "No Custom DocPerms found for Customer!" -ForegroundColor Red
}

Write-Host "`n=== Verifying Custom DocPerms for Dispatch Case ===" -ForegroundColor Cyan

$uri = "$BaseUrl/api/resource/Custom DocPerm?filters=[[`"parent`",`"=`",`"Dispatch Case`"]]&fields=[`"role`",`"read`",`"write`",`"create`",`"submit`"]&limit_page_length=20"
$result = Invoke-RestMethod -Uri $uri -Headers $Headers -Method Get

if ($result.data -and $result.data.Count -gt 0) {
    Write-Host "`nFound $($result.data.Count) Custom DocPerms for Dispatch Case:" -ForegroundColor Green
    $result.data | Format-Table -Property role, read, write, create, submit -AutoSize
} else {
    Write-Host "No Custom DocPerms found for Dispatch Case!" -ForegroundColor Red
}

Write-Host "`n"
