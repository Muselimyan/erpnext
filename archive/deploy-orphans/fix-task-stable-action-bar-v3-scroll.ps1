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
Write-Host "=== Fix Task Stable Action Bar v3 Scroll ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

$data = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $Name)?fields=[`"script`"]" -Headers $Headers -Method Get -TimeoutSec 20).data
$script = $data.script
$hasV3 = $script -match 'stable-task-action-bar-v3-scroll'
Write-Host "Has v3 scroll marker: $(if($hasV3){'Yes'}else{'No'})"

if ($Mode -eq "Check") {
    if ($hasV3) { Write-Host "Status: fixed" -ForegroundColor Green } else { Write-Host "Status: needs deploy" -ForegroundColor Yellow }
    return
}

$old = @'
    bar.append(actions);
    var formLayout = $(frm.wrapper).find(".form-layout").first();
    if (formLayout.length) formLayout.prepend(bar);
}
'@

$new = @'
    bar.attr("data-version", "stable-task-action-bar-v3-scroll");
    bar.css({"position":"static","top":"auto","z-index":"auto"});
    bar.append(actions);

    var firstSection = $(frm.wrapper).find(".form-page:visible .form-section").first();
    if (!firstSection.length) firstSection = $(frm.wrapper).find(".form-page .form-section").first();
    if (firstSection.length) {
        firstSection.before(bar);
        return;
    }

    var formLayout = $(frm.wrapper).find(".form-layout").first();
    if (formLayout.length) formLayout.prepend(bar);
}
'@

if (-not $script.Contains($old)) {
    throw "Expected v2 insertion block not found"
}
$script = $script.Replace($old, $new)

$backupPath = Join-Path $PSScriptRoot ("_backup_Task_Accept_Start_stable_bar_v3_scroll_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".js")
$data.script | Set-Content -Path $backupPath -Encoding UTF8
Write-Host "Backup: $backupPath" -ForegroundColor Green

$body = @{ script = $script } | ConvertTo-Json -Depth 10 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 20 | Out-Null
Write-Host "Stable Task action bar v3 scroll behavior deployed" -ForegroundColor Green
