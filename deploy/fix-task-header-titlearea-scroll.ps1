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
Write-Host "=== Task Header Title Area Scroll ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

$data = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $Name)?fields=[`"script`"]" -Headers $Headers -Method Get -TimeoutSec 20).data
$script = $data.script
$hasOptionA = $script -match 'task_header_option_a_fix'
$hasTitleAreaScroll = $script -match 'task-title-area-scroll-v1'
Write-Host "Has Option A fix: $(if($hasOptionA){'Yes'}else{'No'})"
Write-Host "Has title-area scroll: $(if($hasTitleAreaScroll){'Yes'}else{'No'})"

if ($Mode -eq "Check") {
    if ($hasOptionA -and $hasTitleAreaScroll) { Write-Host "Status: fixed" -ForegroundColor Green } else { Write-Host "Status: needs deploy" -ForegroundColor Yellow }
    return
}

if (-not $hasOptionA) { throw "Option A header fix is missing." }

$backupPath = Join-Path $PSScriptRoot ("_backup_Task_Accept_Start_titlearea_scroll_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".js")
$data.script | Set-Content -Path $backupPath -Encoding UTF8
Write-Host "Backup: $backupPath" -ForegroundColor Green

$needle = "if (fullText) tt.attr('title', fullText);"
$inject = @'
                ta.attr('data-task-title-area-scroll', 'task-title-area-scroll-v1');
                ta.css({'overflow-x':'auto','overflow-y':'hidden','white-space':'nowrap','cursor':'grab','scrollbar-width':'thin','max-width':available + 'px','width':available + 'px','user-select':'none'});
                ta.children().css({'display':'inline-block','white-space':'nowrap','float':'none'});
                ta.find('*').css({'white-space':'nowrap'});
                var fullTitleArea = $.trim(ta.text());
                if (fullTitleArea) ta.attr('title', fullTitleArea);
                ta.off('wheel.taskTitleAreaScroll').on('wheel.taskTitleAreaScroll', function(e) {
                    var ev = e.originalEvent;
                    if (!ev) return;
                    this.scrollLeft += (ev.deltaY || ev.deltaX || 0);
                    e.preventDefault();
                });
                ta.off('mousedown.taskTitleAreaScroll').on('mousedown.taskTitleAreaScroll', function(e) {
                    var el = this;
                    var startX = e.pageX;
                    var startLeft = el.scrollLeft;
                    ta.css('cursor', 'grabbing');
                    $(document).on('mousemove.taskTitleAreaScroll', function(ev) {
                        el.scrollLeft = startLeft - (ev.pageX - startX);
                    });
                    $(document).on('mouseup.taskTitleAreaScroll', function() {
                        ta.css('cursor', 'grab');
                        $(document).off('.taskTitleAreaScroll');
                    });
                    e.preventDefault();
                });
'@

if ($script.Contains($needle) -and -not $hasTitleAreaScroll) {
    $script = $script.Replace($needle, $needle + "`n" + $inject)
} elseif (-not $hasTitleAreaScroll) {
    throw "Could not find title insertion point"
}

$body = @{ script = $script } | ConvertTo-Json -Depth 10 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 20 | Out-Null
Write-Host "Title-area scroll patch deployed" -ForegroundColor Green
