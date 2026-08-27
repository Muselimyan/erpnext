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
Write-Host "=== Task Header Option A Clean Fix ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

$data = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $Name)?fields=[`"script`"]" -Headers $Headers -Method Get -TimeoutSec 20).data
$script = $data.script

$hasStableBar = $script -match 'renderStableTaskActionBar|stable-task-action-bar'
$hasTabsNonsticky = $script -match 'task-tabs-nonsticky-style'
$hasOptionA = $script -match 'task_header_option_a_fix'

Write-Host "Has stable action bar remnants: $(if($hasStableBar){'Yes'}else{'No'})"
Write-Host "Has nonsticky tabs remnants: $(if($hasTabsNonsticky){'Yes'}else{'No'})"
Write-Host "Has Option A header fix: $(if($hasOptionA){'Yes'}else{'No'})"

if ($Mode -eq "Check") {
    if ((-not $hasStableBar) -and (-not $hasTabsNonsticky) -and $hasOptionA) { Write-Host "Status: fixed" -ForegroundColor Green } else { Write-Host "Status: needs deploy" -ForegroundColor Yellow }
    return
}

$backupPath = Join-Path $PSScriptRoot ("_backup_Task_Accept_Start_option_a_clean_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".js")
$data.script | Set-Content -Path $backupPath -Encoding UTF8
Write-Host "Backup: $backupPath" -ForegroundColor Green

$script = [regex]::Replace($script, '\s*renderStableTaskActionBar\(frm\);\s*', "`n", 1)
$script = [regex]::Replace($script, '(?s)\nfunction renderStableTaskActionBar\(frm\) \{.*?\n\}\s*$', "`n")
$script = [regex]::Replace($script, '(?s)\s*if \(!document\.getElementById\("task-tabs-nonsticky-style"\)\) \{.*?document\.head\.appendChild\(taskTabsStyle\);\s*\}\s*', "`n", 1)

$oldHeaderPattern = '(?s)\s*\(function\(\) \{\s*function taskHeaderFixedActions\(\).*?setTimeout\(taskHeaderFixedActions, 1000\);\s*\}\)\(\);\s*'
$script = [regex]::Replace($script, $oldHeaderPattern, "`n", 1)

$optionA = @'
        (function() {
            function task_header_option_a_fix() {
                var page = $(frm.page.wrapper);
                var phc = page.find('.page-head-content').first();
                var ta = page.find('.title-area').first();
                var tt = page.find('.title-text').first();
                var pa = page.find('.page-actions').first();
                if (!phc.length || !ta.length || !pa.length) return;

                var actionWidth = Math.max(pa.outerWidth(true), 260);
                var available = Math.max(phc.width() - actionWidth - 18, 220);

                phc.css({'display':'flex','align-items':'flex-start','gap':'8px','min-width':'0','max-width':'100%','overflow':'visible','flex-wrap':'nowrap'});
                ta.css({'flex':'1 1 auto','min-width':'0','max-width':available + 'px','overflow':'hidden'});
                tt.css({'display':'block','overflow':'hidden','text-overflow':'ellipsis','white-space':'nowrap','max-width':'100%'});
                pa.css({'flex':'0 0 auto','display':'flex','flex-wrap':'nowrap','justify-content':'flex-end','align-items':'flex-start','gap':'4px','overflow':'visible','white-space':'nowrap','z-index':'30'});
                pa.find('.btn').css({'flex':'0 0 auto','white-space':'nowrap'});

                var fullText = $.trim(tt.text());
                if (fullText) tt.attr('title', fullText);
            }
            task_header_option_a_fix();
            setTimeout(task_header_option_a_fix, 100);
            setTimeout(task_header_option_a_fix, 400);
            setTimeout(task_header_option_a_fix, 1000);
            $(window).off('resize.taskHeaderOptionA').on('resize.taskHeaderOptionA', task_header_option_a_fix);
        })();
'@

$refreshMarker = '    refresh(frm) {'
$idx = $script.IndexOf($refreshMarker)
if ($idx -lt 0) { throw "Could not find refresh(frm) block" }
$insertAt = $idx + $refreshMarker.Length
if ($script -notmatch 'task_header_option_a_fix') {
    $script = $script.Substring(0, $insertAt) + "`n" + $optionA + $script.Substring($insertAt)
}

$body = @{ script = $script } | ConvertTo-Json -Depth 10 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 20 | Out-Null
Write-Host "Option A header-only fix deployed" -ForegroundColor Green
