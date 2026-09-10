#Requires -Version 5.1
# Quick push: Task-Product Work Area.js to Test
Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$ConfigPath = Join-Path (Split-Path $PSScriptRoot) "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

$WorkDir = Join-Path (Split-Path $PSScriptRoot) "work"
$FilePath = Join-Path $WorkDir "client\Task-Product Work Area.js"

$Content = Get-Content $FilePath -Raw -Encoding UTF8
if ($Content -match '(?s)^.*?//\s*---\s*\r?\n') {
    $Content = $Content.Substring($Matches[0].Length)
}
$Content = $Content.TrimEnd()
Write-Host "New script: $($Content.Length) chars"

$Json = @{ script = $Content; enabled = 1 } | ConvertTo-Json -Depth 5 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/Task-Product%20Work%20Area" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 60 | Out-Null
Write-Host "Task-Product Work Area: UPDATED" -ForegroundColor Green

# Clear cache
$sshKey = "$env:USERPROFILE\.ssh\vps_erpnext2"
ssh -i $sshKey root@161.97.83.156 "docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
Write-Host "Cache cleared" -ForegroundColor Green
