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

$Name = "Task-Accept Start"
Write-Host "=== Fix New Task Header Accept Button ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

$data = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $Name)?fields=[`"script`"]" -Headers $Headers -Method Get -TimeoutSec 30).data
$script = $data.script

$oldCondition = 'if ((!frm.is_new() || isOrderEntry) && operationalKinds.includes(frm.doc.task_kind) && ["Open", "Working"].includes(frm.doc.status) && frm.doc.custom_accepted_by !== frappe.session.user) {'
$newCondition = 'if (!frm.is_new() && operationalKinds.includes(frm.doc.task_kind) && ["Open", "Working"].includes(frm.doc.status) && frm.doc.custom_accepted_by !== frappe.session.user) {'
$hasOld = $script.Contains($oldCondition)
$hasNew = $script.Contains($newCondition)

Write-Host "Header Accept button allows new Task: $(if($hasOld){'Yes'}else{'No'})"
Write-Host "Header Accept button saved-only: $(if($hasNew){'Yes'}else{'No'})"

if ($Mode -eq "Check") {
    if ($hasNew -and -not $hasOld) { Write-Host "Status: fixed" -ForegroundColor Green } else { Write-Host "Status: needs deploy" -ForegroundColor Yellow }
    return
}

if (-not $hasOld -and $hasNew) {
    Write-Host "Already fixed" -ForegroundColor Green
    return
}
if (-not $hasOld) { throw "Could not find old header Accept button condition" }

$backupPath = Join-Path $PSScriptRoot ("_backup_Task_Accept_Start_new_task_header_accept_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".js")
$data.script | Set-Content -Path $backupPath -Encoding UTF8
Write-Host "Backup: $backupPath" -ForegroundColor Green

$script = $script.Replace($oldCondition, $newCondition)
$body = @{ script = $script } | ConvertTo-Json -Depth 10 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
Write-Host "New Task header Accept / Start visibility fixed" -ForegroundColor Green
