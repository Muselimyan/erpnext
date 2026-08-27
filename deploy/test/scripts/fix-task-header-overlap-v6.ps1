#Requires -Version 5.1
Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$BaseUrl = "https://test.erpnext.am"
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }

$ScriptName = "Task-Header Long Subject Fix"
$NewScript = @'
frappe.ui.form.on('Task', {
    refresh: function(frm) {
        task_header_long_subject_fix();
    }
});

function task_header_long_subject_fix() {
    var oldStyle = document.getElementById('task-header-long-subject-fix');
    if (oldStyle) oldStyle.remove();
    var style = document.createElement('style');
    style.id = 'task-header-long-subject-fix';
    style.textContent = `
body[data-route^="Form/Task"] .page-head {
    overflow: visible !important;
}
body[data-route^="Form/Task"] .page-head .container,
body[data-route^="Form/Task"] .page-head .container-fluid,
body[data-route^="Form/Task"] .page-head .page-head-content,
body[data-route^="Form/Task"] .page-head .standard-actions {
    min-width: 0 !important;
}
body[data-route^="Form/Task"] .page-head .page-head-content {
    display: flex !important;
    align-items: center !important;
    gap: 8px !important;
    flex-wrap: nowrap !important;
    min-height: 44px !important;
    overflow: hidden !important;
}
body[data-route^="Form/Task"] .page-head .title-area {
    min-width: 0 !important;
    flex: 1 1 auto !important;
    max-width: 100% !important;
    overflow: hidden !important;
}
body[data-route^="Form/Task"] .page-head .title-text,
body[data-route^="Form/Task"] .page-head .title-text a,
body[data-route^="Form/Task"] .page-head .title-text span,
body[data-route^="Form/Task"] .page-head h3,
body[data-route^="Form/Task"] .page-head .ellipsis {
    display: block !important;
    white-space: nowrap !important;
    overflow-wrap: normal !important;
    word-break: normal !important;
    overflow: hidden !important;
    text-overflow: ellipsis !important;
    line-height: 1.2 !important;
    max-width: 100% !important;
}
body[data-route^="Form/Task"] .page-head .page-actions,
body[data-route^="Form/Task"] .page-head .standard-actions,
body[data-route^="Form/Task"] .page-head .custom-actions {
    flex: 0 0 auto !important;
    white-space: nowrap !important;
    display: flex !important;
    align-items: center !important;
    justify-content: flex-end !important;
    min-width: 0 !important;
    margin-left: auto !important;
    position: relative !important;
    z-index: 2 !important;
    overflow: visible !important;
}
body[data-route^="Form/Task"] .page-head .page-actions .btn,
body[data-route^="Form/Task"] .page-head .standard-actions .btn,
body[data-route^="Form/Task"] .page-head .custom-actions .btn {
    flex: 0 0 auto !important;
}
@media (max-width: 768px) {
    body[data-route^="Form/Task"] .page-head .page-head-content {
        min-height: 50px !important;
        padding-bottom: 0 !important;
    }
    body[data-route^="Form/Task"] .page-head .title-area {
        max-width: calc(100vw - 150px) !important;
    }
    body[data-route^="Form/Task"] .page-head .page-actions,
    body[data-route^="Form/Task"] .page-head .standard-actions,
    body[data-route^="Form/Task"] .page-head .custom-actions {
        max-width: 112px !important;
    }
    body[data-route^="Form/Task"] .page-head .page-actions .btn,
    body[data-route^="Form/Task"] .page-head .standard-actions .btn,
    body[data-route^="Form/Task"] .page-head .custom-actions .btn {
        max-width: 54px !important;
        overflow: hidden !important;
        text-overflow: ellipsis !important;
        white-space: nowrap !important;
    }
}
`;
    document.head.appendChild(style);
}
'@

$existing = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $ScriptName)?fields=[`"name`",`"script`"]" -Headers $Headers -Method Get -TimeoutSec 30
$backupPath = Join-Path $PSScriptRoot ("_backup_Task_Header_Long_Subject_Fix_v6_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".js")
$existing.data.script | Set-Content -Path $backupPath -Encoding UTF8
$body = @{ script = $NewScript } | ConvertTo-Json -Depth 10 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $ScriptName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
Write-Host "Backup: $backupPath" -ForegroundColor Green
Write-Host "Deployed Task header overlap v6 to test" -ForegroundColor Green
