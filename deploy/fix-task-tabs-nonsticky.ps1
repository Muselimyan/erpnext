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
Write-Host "=== Fix Task Tabs Nonsticky ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

$data = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $Name)?fields=[`"script`"]" -Headers $Headers -Method Get -TimeoutSec 20).data
$script = $data.script
$hasMarker = $script -match 'task-tabs-nonsticky-style'
Write-Host "Has nonsticky tabs style: $(if($hasMarker){'Yes'}else{'No'})"

if ($Mode -eq "Check") {
    if ($hasMarker) { Write-Host "Status: fixed" -ForegroundColor Green } else { Write-Host "Status: needs deploy" -ForegroundColor Yellow }
    return
}

$inject = @'
        if (!document.getElementById("task-tabs-nonsticky-style")) {
            var taskTabsStyle = document.createElement("style");
            taskTabsStyle.id = "task-tabs-nonsticky-style";
            taskTabsStyle.textContent = `
body[data-route^="Form/Task"] .form-tabs-list,
body[data-route^="Form/Task"] .form-tabs,
body[data-route^="Form/Task"] .form-dashboard-section .nav,
body[data-route^="Form/Task"] .form-tabs-sticky-down,
body[data-route^="Form/Task"] .form-tabs-sticky-up {
    position: static !important;
    top: auto !important;
    z-index: auto !important;
}
`;
            document.head.appendChild(taskTabsStyle);
        }
'@

$refreshMarker = '    refresh(frm) {'
if ($script -notmatch [regex]::Escape('task-tabs-nonsticky-style')) {
    $idx = $script.IndexOf($refreshMarker)
    if ($idx -lt 0) { throw "Could not find refresh(frm) block" }
    $insertAt = $idx + $refreshMarker.Length
    $script = $script.Substring(0, $insertAt) + "`n" + $inject + $script.Substring($insertAt)
}

$backupPath = Join-Path $PSScriptRoot ("_backup_Task_Accept_Start_tabs_nonsticky_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".js")
$data.script | Set-Content -Path $backupPath -Encoding UTF8
Write-Host "Backup: $backupPath" -ForegroundColor Green

$body = @{ script = $script } | ConvertTo-Json -Depth 10 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 20 | Out-Null
Write-Host "Task tabs nonsticky patch deployed" -ForegroundColor Green
