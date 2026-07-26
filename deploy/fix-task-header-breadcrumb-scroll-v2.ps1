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
Write-Host "=== Task Header Breadcrumb Scroll v2 ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

$data = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $Name)?fields=[`"script`"]" -Headers $Headers -Method Get -TimeoutSec 20).data
$script = $data.script
$hasOptionA = $script -match 'task_header_option_a_fix'
$hasV2 = $script -match 'task-breadcrumb-scroll-v2'
Write-Host "Has Option A fix: $(if($hasOptionA){'Yes'}else{'No'})"
Write-Host "Has breadcrumb scroll v2: $(if($hasV2){'Yes'}else{'No'})"

if ($Mode -eq "Check") {
    if ($hasOptionA -and $hasV2) { Write-Host "Status: fixed" -ForegroundColor Green } else { Write-Host "Status: needs deploy" -ForegroundColor Yellow }
    return
}

if (-not $hasOptionA) { throw "Option A header fix is missing." }

$backupPath = Join-Path $PSScriptRoot ("_backup_Task_Accept_Start_breadcrumb_scroll_v2_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".js")
$data.script | Set-Content -Path $backupPath -Encoding UTF8
Write-Host "Backup: $backupPath" -ForegroundColor Green

$oldBlock = @'
                if (bc.length) {
                    bc.attr('data-task-breadcrumb-scroll', 'task-breadcrumb-scroll-v1');
                    bc.css({'display':'flex','flex-wrap':'nowrap','overflow-x':'auto','overflow-y':'hidden','white-space':'nowrap','max-width':'100%','scrollbar-width':'thin','cursor':'ew-resize'});
                    bc.find('li, .breadcrumb-item, a').css({'flex':'0 0 auto','white-space':'nowrap'});
                    var fullBreadcrumb = $.trim(bc.text());
                    if (fullBreadcrumb) bc.attr('title', fullBreadcrumb);
                }
'@

$newBlock = @'
                if (bc.length) {
                    bc.attr('data-task-breadcrumb-scroll', 'task-breadcrumb-scroll-v2');
                    var bcWidth = Math.max(available, 220);
                    bc.css({'display':'block','overflow-x':'auto','overflow-y':'hidden','white-space':'nowrap','max-width':bcWidth + 'px','width':bcWidth + 'px','scrollbar-width':'thin','cursor':'grab','user-select':'none'});
                    bc.find('li, .breadcrumb-item, a, span').css({'display':'inline-block','float':'none','white-space':'nowrap'});
                    var fullBreadcrumb = $.trim(bc.text());
                    if (fullBreadcrumb) bc.attr('title', fullBreadcrumb);

                    bc.off('wheel.taskBreadcrumbScroll').on('wheel.taskBreadcrumbScroll', function(e) {
                        if (Math.abs(e.originalEvent.deltaY) > Math.abs(e.originalEvent.deltaX)) {
                            this.scrollLeft += e.originalEvent.deltaY;
                            e.preventDefault();
                        }
                    });
                    bc.off('mousedown.taskBreadcrumbScroll').on('mousedown.taskBreadcrumbScroll', function(e) {
                        var el = this;
                        var startX = e.pageX;
                        var startLeft = el.scrollLeft;
                        bc.css('cursor', 'grabbing');
                        $(document).on('mousemove.taskBreadcrumbScroll', function(ev) {
                            el.scrollLeft = startLeft - (ev.pageX - startX);
                        });
                        $(document).on('mouseup.taskBreadcrumbScroll', function() {
                            bc.css('cursor', 'grab');
                            $(document).off('.taskBreadcrumbScroll');
                        });
                        e.preventDefault();
                    });
                }
'@

if ($script.Contains($oldBlock)) {
    $script = $script.Replace($oldBlock, $newBlock)
} elseif (-not $hasV2) {
    throw "Could not find breadcrumb v1 block to replace"
}

$body = @{ script = $script } | ConvertTo-Json -Depth 10 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 20 | Out-Null
Write-Host "Forced breadcrumb scroll v2 deployed" -ForegroundColor Green
