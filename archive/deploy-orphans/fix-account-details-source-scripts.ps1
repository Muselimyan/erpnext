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

Write-Host "=== Fix Account Details Source Scripts ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

# Script 1: Task-Product Work Area
$name1 = "Task-Product Work Area"
$data1 = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $name1)?fields=[`"script`"]" -Headers $Headers -Method Get -TimeoutSec 30).data
$guard1 = 'if (frm.doc.task_kind === "Account details") return;'
$anchor1 = 'frappe.ui.form.on("Task", {'
$hasGuard1 = $data1.script.Contains($guard1)

# Script 2: Task-Product Lines Display
$name2 = "Task-Product Lines Display"
$data2 = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $name2)?fields=[`"script`"]" -Headers $Headers -Method Get -TimeoutSec 30).data
$guard2 = 'if (frm.doc.task_kind === "Account details") return;'
$anchor2 = 'refresh: function(frm) {'
$hasGuard2 = $data2.script.Contains($guard2)

# Script 3: Task-Dispatch Packing Usability
$name3 = "Task-Dispatch Packing Usability"
$data3 = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $name3)?fields=[`"script`"]" -Headers $Headers -Method Get -TimeoutSec 30).data
$guard3 = 'if (frm.doc.task_kind === "Account details") return;'
$anchor3 = 'refresh(frm) {'
$hasGuard3 = $data3.script.Contains($guard3)

Write-Host "Product Work Area has Account details guard: $(if($hasGuard1){'Yes'}else{'No'})"
Write-Host "Product Lines Display has Account details guard: $(if($hasGuard2){'Yes'}else{'No'})"
Write-Host "Dispatch Packing Usability has Account details guard: $(if($hasGuard3){'Yes'}else{'No'})"

if ($Mode -eq "Check") {
    if ($hasGuard1 -and $hasGuard2 -and $hasGuard3) { Write-Host "Status: fixed" -ForegroundColor Green } else { Write-Host "Status: needs deploy" -ForegroundColor Yellow }
    return
}

if ($hasGuard1 -and $hasGuard2 -and $hasGuard3) {
    Write-Host "Already fixed" -ForegroundColor Green
    return
}

$backupPath = Join-Path $PSScriptRoot ("_backup_account_details_source_scripts_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".json")
@{ product_work = $data1.script; product_lines = $data2.script; dispatch_packing = $data3.script } | ConvertTo-Json -Depth 10 | Set-Content -Path $backupPath -Encoding UTF8
Write-Host "Backup: $backupPath" -ForegroundColor Green

# Patch Script 1
if (-not $hasGuard1) {
    $refreshAnchor = '    refresh(frm) {'
    if (-not $data1.script.Contains($refreshAnchor)) { throw "Could not find refresh function in $name1" }
    $script1 = $data1.script.Replace($refreshAnchor, $refreshAnchor + "`n        " + $guard1)
    $body1 = @{ script = $script1 } | ConvertTo-Json -Depth 10 -Compress
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $name1)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body1)) -TimeoutSec 30 | Out-Null
    Write-Host "$name1 patched" -ForegroundColor Green
}

# Patch Script 2
if (-not $hasGuard2) {
    if (-not $data2.script.Contains($anchor2)) { throw "Could not find anchor in $name2" }
    $script2 = $data2.script.Replace($anchor2, $anchor2 + "`n        " + $guard2)
    $body2 = @{ script = $script2 } | ConvertTo-Json -Depth 10 -Compress
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $name2)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body2)) -TimeoutSec 30 | Out-Null
    Write-Host "$name2 patched" -ForegroundColor Green
}

# Patch Script 3
if (-not $hasGuard3) {
    if (-not $data3.script.Contains($anchor3)) { throw "Could not find anchor in $name3" }
    $script3 = $data3.script.Replace($anchor3, $anchor3 + "`n        " + $guard3)
    $body3 = @{ script = $script3 } | ConvertTo-Json -Depth 10 -Compress
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $name3)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body3)) -TimeoutSec 30 | Out-Null
    Write-Host "$name3 patched" -ForegroundColor Green
}

Write-Host "Account details source scripts fixed" -ForegroundColor Green
