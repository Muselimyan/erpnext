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
Write-Host "=== Task Header Buttons Layout v4 Diagnostic ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

$NewScript = @'
frappe.ui.form.on('Task', {
    refresh: function(frm) {
        task_header_buttons_layout_v4_diagnostic(frm);
        setTimeout(function() { task_header_buttons_layout_v4_diagnostic(frm); }, 100);
        setTimeout(function() { task_header_buttons_layout_v4_diagnostic(frm); }, 500);
        setTimeout(function() { task_header_buttons_layout_v4_diagnostic(frm); }, 1200);
        setTimeout(function() { task_header_buttons_layout_v4_diagnostic(frm); }, 2500);
    }
});

function task_header_buttons_layout_v4_diagnostic(frm) {
    var styleId = 'task-header-buttons-layout-v4-diagnostic';
    var existingStyle = document.getElementById(styleId);
    if (existingStyle) existingStyle.remove();

    var style = document.createElement('style');
    style.id = styleId;
    style.textContent = `
/* CRITICAL: Force page-head to be relative container */
.page-head,
body .page-head,
html body .page-head,
.layout-main .page-head,
.layout-main-section .page-head {
    position: relative !important;
    overflow: visible !important;
    min-height: 40px !important;
}

/* CRITICAL: page-head-content must allow absolute positioning inside */
.page-head .page-head-content,
body .page-head .page-head-content,
html body .page-head .page-head-content,
.layout-main .page-head .page-head-content {
    position: relative !important;
    min-width: 0 !important;
    max-width: 100% !important;
    overflow: visible !important;
    padding-right: 440px !important;
    min-height: 38px !important;
}

/* Title area: must stay within left space */
.page-head .title-area,
body .page-head .title-area,
html body .page-head .title-area {
    min-width: 0 !important;
    max-width: 100% !important;
    overflow: hidden !important;
    flex: 1 1 auto !important;
}

/* Title text: truncate with ellipsis */
.page-head .title-text,
body .page-head .title-text,
html body .page-head .title-text,
.page-head .title-text a,
.page-head .title-text span,
.page-head .ellipsis,
.page-head h3 {
    display: block !important;
    min-width: 0 !important;
    max-width: 100% !important;
    overflow: hidden !important;
    text-overflow: ellipsis !important;
    white-space: nowrap !important;
    word-break: normal !important;
}

/* Breadcrumb: also truncate */
.page-head .breadcrumb,
body .page-head .breadcrumb,
.page-head .breadcrumb-item,
.page-head .breadcrumb-item a {
    min-width: 0 !important;
    max-width: 100% !important;
    overflow: hidden !important;
    text-overflow: ellipsis !important;
    white-space: nowrap !important;
}

/* CRITICAL: Fix page-actions to top-right */
.page-head .page-actions,
body .page-head .page-actions,
html body .page-head .page-actions,
.layout-main .page-head .page-actions {
    position: absolute !important;
    top: 0 !important;
    right: 0 !important;
    width: 430px !important;
    max-width: 430px !important;
    min-width: 430px !important;
    display: flex !important;
    flex-wrap: wrap !important;
    justify-content: flex-end !important;
    align-items: flex-start !important;
    gap: 4px !important;
    z-index: 200 !important;
    overflow: visible !important;
    background: var(--bg-color, #ffffff) !important;
    padding: 0 !important;
    margin: 0 !important;
}

/* Standard/custom actions inside page-actions */
.page-head .page-actions .standard-actions,
.page-head .page-actions .custom-actions,
body .page-head .page-actions .standard-actions,
body .page-head .page-actions .custom-actions {
    display: flex !important;
    flex-wrap: wrap !important;
    justify-content: flex-end !important;
    align-items: flex-start !important;
    gap: 4px !important;
    min-width: 0 !important;
    max-width: 100% !important;
}

/* Buttons: prevent overflow */
.page-head .page-actions .btn,
body .page-head .page-actions .btn,
.page-head .standard-actions .btn,
.page-head .custom-actions .btn {
    flex: 0 0 auto !important;
    max-width: 180px !important;
    overflow: hidden !important;
    text-overflow: ellipsis !important;
    white-space: nowrap !important;
}

/* Responsive: on narrow screens, move buttons below title */
@media (max-width: 1280px) {
    .page-head .page-head-content,
    body .page-head .page-head-content {
        padding-right: 0 !important;
        padding-bottom: 42px !important;
    }
    .page-head .page-actions,
    body .page-head .page-actions {
        position: static !important;
        width: 100% !important;
        max-width: 100% !important;
        min-width: 0 !important;
        justify-content: flex-start !important;
        margin-top: 8px !important;
        background: transparent !important;
    }
    .page-head .page-actions .standard-actions,
    .page-head .page-actions .custom-actions {
        justify-content: flex-start !important;
    }
}
`;
    document.head.appendChild(style);

    // Diagnostic logging
    if (frm && frm.page && frm.page.wrapper) {
        var wrapper = $(frm.page.wrapper);
        var pageHead = wrapper.find('.page-head');
        var pageHeadContent = pageHead.find('.page-head-content');
        var titleArea = pageHead.find('.title-area');
        var pageActions = pageHead.find('.page-actions');
        
        console.log('[TaskHeaderFix] Diagnostic:', {
            pageHead: pageHead.length,
            pageHeadContent: pageHeadContent.length,
            titleArea: titleArea.length,
            pageActions: pageActions.length,
            pageActionsPosition: pageActions.css('position'),
            pageActionsTop: pageActions.css('top'),
            pageActionsRight: pageActions.css('right'),
            pageHeadContentPaddingRight: pageHeadContent.css('padding-right')
        });

        // Force tooltip on title
        var titleText = titleArea.find('.title-text').first();
        if (titleText.length) {
            var fullText = $.trim(titleText.text());
            if (fullText) titleText.attr('title', fullText);
        }
    }
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
            $hasV4 = $existing.data.script -match 'task_header_buttons_layout_v4_diagnostic'
            $hasDiagnostic = $existing.data.script -match 'Diagnostic logging'
            $hasMaxSpecificity = $existing.data.script -match 'html body .page-head'
            Write-Host "Has v4 diagnostic function: $(if($hasV4){'Yes'}else{'No'})"
            Write-Host "Has console logging: $(if($hasDiagnostic){'Yes'}else{'No'})"
            Write-Host "Has max CSS specificity: $(if($hasMaxSpecificity){'Yes'}else{'No'})"
            if ($hasV4 -and $hasDiagnostic -and $hasMaxSpecificity) { Write-Host "Status: fixed" -ForegroundColor Green } else { Write-Host "Status: needs deploy" -ForegroundColor Yellow }
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
        $backupPath = Join-Path $PSScriptRoot ("_backup_Task_Header_Long_Subject_Fix_v4_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".js")
        $existing.data.script | Set-Content -Path $backupPath -Encoding UTF8
        Write-Host "Backup: $backupPath" -ForegroundColor Green
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $ScriptName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 20 | Out-Null
        Write-Host "Updated existing Client Script" -ForegroundColor Green
    } else {
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 20 | Out-Null
        Write-Host "Created Client Script" -ForegroundColor Green
    }

    Write-Host "`nTask header layout v4 diagnostic deployed" -ForegroundColor Green
    Write-Host "`nNext steps:" -ForegroundColor Cyan
    Write-Host "1. Refresh Task page on test (Ctrl+F5)" -ForegroundColor White
    Write-Host "2. Open browser console (F12)" -ForegroundColor White
    Write-Host "3. Look for [TaskHeaderFix] Diagnostic log" -ForegroundColor White
    Write-Host "4. Check if buttons are now visible" -ForegroundColor White
} catch {
    Write-Host "`nERROR: $_" -ForegroundColor Red
    throw
}
