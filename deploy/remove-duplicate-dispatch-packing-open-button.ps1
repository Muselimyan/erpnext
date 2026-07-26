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

$Name = "Task-Dispatch Packing Usability"
Write-Host "=== Remove Duplicate Dispatch Packing Open Button ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

$data = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $Name)?fields=[`"script`"]" -Headers $Headers -Method Get -TimeoutSec 20).data
$script = $data.script

$hasDuplicateOpen = $script -match 'Open Dispatch Case / Items'
$hasGroup = $script -match 'Dispatch & Packing Work|Dispatch \\u0026 Packing Work'

Write-Host "Has duplicate Open Dispatch Case / Items button: $(if($hasDuplicateOpen){'Yes'}else{'No'})"
Write-Host "Has Dispatch & Packing Work group text: $(if($hasGroup){'Yes'}else{'No'})"

if ($Mode -eq "Check") {
    if (-not $hasDuplicateOpen) { Write-Host "Status: fixed" -ForegroundColor Green } else { Write-Host "Status: needs deploy" -ForegroundColor Yellow }
    return
}

$backupPath = Join-Path $PSScriptRoot ("_backup_Task_Dispatch_Packing_Usability_no_duplicate_open_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".js")
$data.script | Set-Content -Path $backupPath -Encoding UTF8
Write-Host "Backup: $backupPath" -ForegroundColor Green

$patterns = @(
'(?s)\s*frm\.add_custom_button\(__\("Open Dispatch Case / Items"\),\s*function\(\)\s*\{\s*frappe\.set_route\("Form",\s*"Dispatch Case",\s*frm\.doc\.dispatch_case\);\s*\},\s*__\("Dispatch & Packing Work"\)\);',
'(?s)\s*frm\.add_custom_button\(__\("Open Dispatch Case / Items"\),\s*function\(\)\s*\{\s*frappe\.set_route\("Form",\s*"Dispatch Case",\s*frm\.doc\.dispatch_case\);\s*\},\s*__\("Dispatch \\u0026 Packing Work"\)\);'
)

$before = $script
foreach ($p in $patterns) {
    $script = [regex]::Replace($script, $p, "", 1)
}

if ($script -eq $before -and $hasDuplicateOpen) {
    throw "Could not find exact duplicate button block to remove"
}

$body = @{ script = $script } | ConvertTo-Json -Depth 10 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 20 | Out-Null
Write-Host "Duplicate Dispatch & Packing Work open button removed" -ForegroundColor Green
