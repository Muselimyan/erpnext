#Requires -Version 5.1
param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check",
    [ValidateSet("test", "main")]
    [string]$Target = "test"
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$BaseUrl = if ($Target -eq "test") { "https://test.erpnext.am" } else { "https://erpnext.am" }
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }

$Name = "Task-before-save-policy"
Write-Host "=== Fix Account details Before Save Policy ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

$data = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script/$(Enc $Name)?fields=[`"script`"]" -Headers $Headers -Method Get -TimeoutSec 30).data
$script = $data.script

$accountLine = '    "Account details": ["Ops - Accounting", "Ops - Finance", "Ops - Directors"],'
$hasAccountDetails = $script.Contains($accountLine)
Write-Host "Before-save policy has Account details roles: $(if($hasAccountDetails){'Yes'}else{'No'})"

if ($Mode -eq "Check") {
    if ($hasAccountDetails) { Write-Host "Status: fixed" -ForegroundColor Green } else { Write-Host "Status: needs deploy" -ForegroundColor Yellow }
    return
}

if ($hasAccountDetails) {
    Write-Host "Already fixed" -ForegroundColor Green
    return
}

$anchor = '    "Write-off Approval": ["Ops - Directors"],'
if (-not $script.Contains($anchor)) { throw "Could not find Write-off Approval anchor" }

$backupPath = Join-Path $PSScriptRoot ("_backup_Task_before_save_policy_account_details_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".py")
$data.script | Set-Content -Path $backupPath -Encoding UTF8
Write-Host "Backup: $backupPath" -ForegroundColor Green

$script = $script.Replace($anchor, $anchor + "`n" + $accountLine)
$body = @{ script = $script } | ConvertTo-Json -Depth 10 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
Write-Host "Account details before-save roles fixed" -ForegroundColor Green
