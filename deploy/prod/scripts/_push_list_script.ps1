$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

$ScriptContent = Get-Content (Join-Path (Join-Path $PSScriptRoot "..") "_temp_task_list.js") -Raw
Write-Host "Script length: $($ScriptContent.Length) chars"

$escaped = $ScriptContent.Replace('\', '\\').Replace('"', '\"').Replace("`r`n", '\n').Replace("`n", '\n').Replace("`t", '\t')
$Body = '{"script":"' + $escaped + '"}'
Write-Host "JSON body length: $($Body.Length) chars"

$Uri = "$BaseUrl/api/resource/Client%20Script/Global-Mobile%20Back%20Button%20List"
Write-Host "Sending PUT to $Uri ..."

try {
    $r = Invoke-RestMethod -Uri $Uri -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($Body)) -TimeoutSec 60
    Write-Host "Done! Updated." -ForegroundColor Green
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}
