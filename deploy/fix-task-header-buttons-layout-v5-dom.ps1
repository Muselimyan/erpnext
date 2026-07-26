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

$ScriptName = "Task-Header Long Subject Fix"
Write-Host "=== Task Header Buttons Layout v5 DOM ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

$NewScript = @'
frappe.ui.form.on('Task', {
    refresh: function(frm) {
        task_header_fix_dom_v5(frm);
        setTimeout(function() { task_header_fix_dom_v5(frm); }, 150);
        setTimeout(function() { task_header_fix_dom_v5(frm); }, 600);
        setTimeout(function() { task_header_fix_dom_v5(frm); }, 1500);
    }
});

function task_header_fix_dom_v5(frm) {
    if (!frm || !frm.page || !frm.page.wrapper) return;

    var wrapper = $(frm.page.wrapper);
    var pageHead = wrapper.find('.page-head').first();
    if (!pageHead.length) return;

    var pageHeadContent = pageHead.find('.page-head-content').first();
    var titleArea = pageHead.find('.title-area').first();
    var pageActions = pageHead.find('.page-actions').first();

    if (!pageHeadContent.length || !titleArea.length || !pageActions.length) {
        console.warn('[TaskHeaderFix] Missing elements:', {
            pageHeadContent: pageHeadContent.length,
            titleArea: titleArea.length,
            pageActions: pageActions.length
        });
        return;
    }

    // Mark as processed to avoid infinite loops
    if (pageHead.data('task-header-fixed-v5')) return;
    pageHead.data('task-header-fixed-v5', true);

    // Force page-head to be relative container
    pageHead.css({
        'position': 'relative',
        'overflow': 'visible',
        'min-height': '40px'
    });

    // Create wrapper for title area if not exists
    if (!pageHeadContent.find('.task-title-wrapper-v5').length) {
        titleArea.wrap('<div class="task-title-wrapper-v5"></div>');
    }
    var titleWrapper = pageHeadContent.find('.task-title-wrapper-v5').first();

    // Style title wrapper
    titleWrapper.css({
        'min-width': '0',
        'max-width': 'calc(100% - 450px)',
        'overflow': 'hidden',
        'flex': '1 1 auto',
        'margin-right': '10px'
    });

    // Style title text to truncate
    titleArea.find('.title-text, .ellipsis, h3').css({
        'display': 'block',
        'overflow': 'hidden',
        'text-overflow': 'ellipsis',
        'white-space': 'nowrap',
        'max-width': '100%'
    });

    // Add tooltip
    var titleText = titleArea.find('.title-text').first();
    if (titleText.length) {
        var fullText = $.trim(titleText.text());
        if (fullText) titleText.attr('title', fullText);
    }

    // Detach page-actions from flow and position absolutely
    pageActions.css({
        'position': 'absolute',
        'top': '0',
        'right': '0',
        'width': '440px',
        'max-width': '440px',
        'min-width': '440px',
        'display': 'flex',
        'flex-wrap': 'wrap',
        'justify-content': 'flex-end',
        'align-items': 'flex-start',
        'gap': '4px',
        'z-index': '200',
        'background': 'var(--bg-color, #fff)',
        'padding': '0',
        'margin': '0'
    });

    // Ensure page-head-content has padding for absolute buttons
    pageHeadContent.css({
        'position': 'relative',
        'padding-right': '450px',
        'min-height': '38px',
        'overflow': 'visible'
    });

    // Style buttons to prevent overflow
    pageActions.find('.btn').css({
        'max-width': '180px',
        'overflow': 'hidden',
        'text-overflow': 'ellipsis',
        'white-space': 'nowrap'
    });

    // Responsive: on narrow screens
    function adjustForWidth() {
        if (window.innerWidth <= 1280) {
            pageHeadContent.css({
                'padding-right': '0',
                'padding-bottom': '42px'
            });
            pageActions.css({
                'position': 'static',
                'width': '100%',
                'max-width': '100%',
                'min-width': '0',
                'justify-content': 'flex-start',
                'margin-top': '8px',
                'background': 'transparent'
            });
        } else {
            pageHeadContent.css({
                'padding-right': '450px',
                'padding-bottom': '0'
            });
            pageActions.css({
                'position': 'absolute',
                'top': '0',
                'right': '0',
                'width': '440px',
                'max-width': '440px',
                'min-width': '440px',
                'justify-content': 'flex-end',
                'margin-top': '0',
                'background': 'var(--bg-color, #fff)'
            });
        }
    }

    adjustForWidth();
    $(window).off('resize.taskHeaderFix').on('resize.taskHeaderFix', adjustForWidth);

    console.log('[TaskHeaderFix v5] Applied DOM manipulation');
}
'@

try {
    $existing = $null
    try {
        $existing = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $ScriptName)?fields=[`"name`",`"script`"]" -Headers $Headers -Method Get -TimeoutSec 20
    } catch {}

    if ($Mode -eq "Check") {
        Write-Host "Script exists: $(if($existing){'Yes'}else{'No'})"
        if ($existing) {
            $hasV5 = $existing.data.script -match 'task_header_fix_dom_v5'
            $hasDOMManip = $existing.data.script -match 'pageActions\.css'
            $hasWrapper = $existing.data.script -match 'task-title-wrapper-v5'
            Write-Host "Has v5 DOM function: $(if($hasV5){'Yes'}else{'No'})"
            Write-Host "Has DOM manipulation: $(if($hasDOMManip){'Yes'}else{'No'})"
            Write-Host "Has title wrapper: $(if($hasWrapper){'Yes'}else{'No'})"
            if ($hasV5 -and $hasDOMManip -and $hasWrapper) { Write-Host "Status: fixed" -ForegroundColor Green } else { Write-Host "Status: needs deploy" -ForegroundColor Yellow }
        } else {
            Write-Host "Status: needs deploy" -ForegroundColor Yellow
        }
        return
    }

    $body = @{
        doctype = "Client Script"
        name = $ScriptName
        dt = "Task"
        view = "Form"
        enabled = 1
        script = $NewScript
    } | ConvertTo-Json -Depth 10 -Compress

    if ($existing) {
        $backupPath = Join-Path $PSScriptRoot ("_backup_Task_Header_Long_Subject_Fix_v5_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".js")
        $existing.data.script | Set-Content -Path $backupPath -Encoding UTF8
        Write-Host "Backup: $backupPath" -ForegroundColor Green
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $ScriptName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 20 | Out-Null
        Write-Host "Updated existing Client Script" -ForegroundColor Green
    } else {
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 20 | Out-Null
        Write-Host "Created Client Script" -ForegroundColor Green
    }

    Write-Host "`nTask header layout v5 DOM deployed" -ForegroundColor Green
    Write-Host "`nThis version uses JavaScript to:" -ForegroundColor Cyan
    Write-Host "  - Directly manipulate DOM elements" -ForegroundColor White
    Write-Host "  - Force button area to top-right position" -ForegroundColor White
    Write-Host "  - Wrap and truncate title text" -ForegroundColor White
    Write-Host "  - Add responsive behavior for narrow screens" -ForegroundColor White
} catch {
    Write-Host "`nERROR: $_" -ForegroundColor Red
    throw
}
