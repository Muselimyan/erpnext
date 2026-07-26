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
Write-Host "=== Task Header Breadcrumb Scroll ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

$data = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $Name)?fields=[`"script`"]" -Headers $Headers -Method Get -TimeoutSec 20).data
$script = $data.script
$hasOptionA = $script -match 'task_header_option_a_fix'
$hasBreadcrumbScroll = $script -match 'task-breadcrumb-scroll-v1'
Write-Host "Has Option A fix: $(if($hasOptionA){'Yes'}else{'No'})"
Write-Host "Has breadcrumb scroll: $(if($hasBreadcrumbScroll){'Yes'}else{'No'})"

if ($Mode -eq "Check") {
    if ($hasOptionA -and $hasBreadcrumbScroll) { Write-Host "Status: fixed" -ForegroundColor Green } else { Write-Host "Status: needs deploy" -ForegroundColor Yellow }
    return
}

if (-not $hasOptionA) { throw "Option A header fix is missing." }

$backupPath = Join-Path $PSScriptRoot ("_backup_Task_Accept_Start_breadcrumb_scroll_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".js")
$data.script | Set-Content -Path $backupPath -Encoding UTF8
Write-Host "Backup: $backupPath" -ForegroundColor Green

$insertAfter = "var tt = page.find('.title-text').first();"
$addLine = "`n                var bc = page.find('.breadcrumb').first();"
if ($script.Contains($insertAfter) -and $script -notmatch "var bc = page.find\('\.breadcrumb'\)") {
    $script = $script.Replace($insertAfter, $insertAfter + $addLine)
}

$insertAfter2 = "tt.css({'display':'block','overflow-x':'auto','overflow-y':'hidden','text-overflow':'clip','white-space':'nowrap','max-width':'100%','scrollbar-width':'thin','cursor':'ew-resize'});"
$breadcrumbCss = @'
                if (bc.length) {
                    bc.attr('data-task-breadcrumb-scroll', 'task-breadcrumb-scroll-v1');
                    bc.css({'display':'flex','flex-wrap':'nowrap','overflow-x':'auto','overflow-y':'hidden','white-space':'nowrap','max-width':'100%','scrollbar-width':'thin','cursor':'ew-resize'});
                    bc.find('li, .breadcrumb-item, a').css({'flex':'0 0 auto','white-space':'nowrap'});
                    var fullBreadcrumb = $.trim(bc.text());
                    if (fullBreadcrumb) bc.attr('title', fullBreadcrumb);
                }
'@

if ($script.Contains($insertAfter2) -and -not $hasBreadcrumbScroll) {
    $script = $script.Replace($insertAfter2, $insertAfter2 + "`n" + $breadcrumbCss)
} elseif (-not $hasBreadcrumbScroll) {
    throw "Could not find subject scroll CSS line to extend"
}

$body = @{ script = $script } | ConvertTo-Json -Depth 10 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 20 | Out-Null
Write-Host "Scrollable breadcrumb/header patch deployed" -ForegroundColor Green
