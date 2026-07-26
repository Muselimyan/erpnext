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
Write-Host "=== Task Header Buttons Layout v3 ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

$NewScript = @'
frappe.ui.form.on('Task', {
    refresh: function(frm) {
        task_header_buttons_layout_v3(frm);
        setTimeout(function() { task_header_buttons_layout_v3(frm); }, 200);
        setTimeout(function() { task_header_buttons_layout_v3(frm); }, 800);
        setTimeout(function() { task_header_buttons_layout_v3(frm); }, 1500);
    }
});

function task_header_buttons_layout_v3(frm) {
    if (!document.getElementById('task-header-buttons-layout-v3')) {
        var style = document.createElement('style');
        style.id = 'task-header-buttons-layout-v3';
        style.textContent = `
body[data-route^="Form/Task"] .page-head {
    overflow: visible !important;
}
body[data-route^="Form/Task"] .page-head .container,
body[data-route^="Form/Task"] .page-head .container-fluid,
body[data-route^="Form/Task"] .page-head .page-head-content {
    position: relative !important;
    min-width: 0 !important;
    max-width: 100% !important;
    overflow: visible !important;
}
body[data-route^="Form/Task"] .page-head .page-head-content {
    min-height: 34px !important;
    padding-right: 430px !important;
}
body[data-route^="Form/Task"] .page-head .title-area,
body[data-route^="Form/Task"] .page-head .title-area .title-text,
body[data-route^="Form/Task"] .page-head .title-area .ellipsis,
body[data-route^="Form/Task"] .page-head .breadcrumb,
body[data-route^="Form/Task"] .page-head .breadcrumb-item,
body[data-route^="Form/Task"] .page-head .breadcrumb-item a {
    min-width: 0 !important;
    max-width: 100% !important;
    overflow: hidden !important;
    text-overflow: ellipsis !important;
    white-space: nowrap !important;
}
body[data-route^="Form/Task"] .page-head .page-actions {
    position: absolute !important;
    top: 0 !important;
    right: 0 !important;
    width: 420px !important;
    max-width: 420px !important;
    min-width: 420px !important;
    display: flex !important;
    flex-wrap: wrap !important;
    justify-content: flex-end !important;
    align-items: flex-start !important;
    gap: 4px !important;
    z-index: 100 !important;
    overflow: visible !important;
    background: var(--bg-color, #fff) !important;
}
body[data-route^="Form/Task"] .page-head .standard-actions,
body[data-route^="Form/Task"] .page-head .custom-actions {
    display: flex !important;
    flex-wrap: wrap !important;
    justify-content: flex-end !important;
    align-items: flex-start !important;
    gap: 4px !important;
    min-width: 0 !important;
    max-width: 100% !important;
}
body[data-route^="Form/Task"] .page-head .page-actions .btn,
body[data-route^="Form/Task"] .page-head .standard-actions .btn,
body[data-route^="Form/Task"] .page-head .custom-actions .btn {
    flex: 0 0 auto !important;
    max-width: 175px !important;
    overflow: hidden !important;
    text-overflow: ellipsis !important;
    white-space: nowrap !important;
}
@media (max-width: 1250px) {
    body[data-route^="Form/Task"] .page-head .page-head-content {
        padding-right: 0 !important;
        padding-bottom: 34px !important;
    }
    body[data-route^="Form/Task"] .page-head .page-actions {
        position: static !important;
        width: 100% !important;
        max-width: 100% !important;
        min-width: 0 !important;
        justify-content: flex-start !important;
        margin-top: 6px !important;
        background: transparent !important;
    }
    body[data-route^="Form/Task"] .page-head .standard-actions,
    body[data-route^="Form/Task"] .page-head .custom-actions {
        justify-content: flex-start !important;
    }
}
`;
        document.head.appendChild(style);
    }

    var pageHead = frm && frm.page && frm.page.wrapper ? $(frm.page.wrapper).find('.page-head') : $('.page-head');
    var titleText = pageHead.find('.title-text').first();
    if (titleText.length) {
        var fullText = $.trim(titleText.text());
        if (fullText) titleText.attr('title', fullText);
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
            $hasV3 = $existing.data.script -match 'task_header_buttons_layout_v3'
            $hasFixedActions = $existing.data.script -match 'position: absolute.*!important'
            $hasReservedPadding = $existing.data.script -match 'padding-right: 430px'
            Write-Host "Has v3 function: $(if($hasV3){'Yes'}else{'No'})"
            Write-Host "Has fixed button area: $(if($hasFixedActions){'Yes'}else{'No'})"
            Write-Host "Has reserved title padding: $(if($hasReservedPadding){'Yes'}else{'No'})"
            if ($hasV3 -and $hasFixedActions -and $hasReservedPadding) { Write-Host "Status: fixed" -ForegroundColor Green } else { Write-Host "Status: needs deploy" -ForegroundColor Yellow }
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
        $backupPath = Join-Path $PSScriptRoot ("_backup_Task_Header_Long_Subject_Fix_v3_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".js")
        $existing.data.script | Set-Content -Path $backupPath -Encoding UTF8
        Write-Host "Backup: $backupPath" -ForegroundColor Green
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $ScriptName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 20 | Out-Null
        Write-Host "Updated existing Client Script" -ForegroundColor Green
    } else {
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 20 | Out-Null
        Write-Host "Created Client Script" -ForegroundColor Green
    }

    Write-Host "Task header layout v3 deployed" -ForegroundColor Green
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    throw
}
