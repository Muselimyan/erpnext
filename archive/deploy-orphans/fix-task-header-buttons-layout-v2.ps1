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
Write-Host "=== Task Header Buttons Layout v2 ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

$NewScript = @'
frappe.ui.form.on('Task', {
    refresh: function(frm) {
        task_header_buttons_layout_v2();
        setTimeout(task_header_buttons_layout_v2, 300);
        setTimeout(task_header_buttons_layout_v2, 1000);
    }
});

function task_header_buttons_layout_v2() {
    if (!document.getElementById('task-header-buttons-layout-v2')) {
        var style = document.createElement('style');
        style.id = 'task-header-buttons-layout-v2';
        style.textContent = `
body[data-route^="Form/Task"] .page-head,
body[data-route^="Form/Task"] .page-head .container,
body[data-route^="Form/Task"] .page-head .container-fluid,
body[data-route^="Form/Task"] .page-head .page-head-content {
    min-width: 0 !important;
    max-width: 100% !important;
    overflow: visible !important;
}
body[data-route^="Form/Task"] .page-head .page-head-content {
    display: grid !important;
    grid-template-columns: minmax(0, 1fr) max-content !important;
    grid-template-areas: "title actions" !important;
    column-gap: 10px !important;
    row-gap: 6px !important;
    align-items: start !important;
}
body[data-route^="Form/Task"] .page-head .title-area {
    grid-area: title !important;
    min-width: 0 !important;
    max-width: 100% !important;
    overflow: hidden !important;
}
body[data-route^="Form/Task"] .page-head .title-text,
body[data-route^="Form/Task"] .page-head .title-text a,
body[data-route^="Form/Task"] .page-head .title-text span,
body[data-route^="Form/Task"] .page-head .ellipsis,
body[data-route^="Form/Task"] .page-head h3 {
    display: block !important;
    max-width: 100% !important;
    min-width: 0 !important;
    overflow: hidden !important;
    text-overflow: ellipsis !important;
    white-space: nowrap !important;
    word-break: normal !important;
}
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
    grid-area: actions !important;
    min-width: 260px !important;
    max-width: min(520px, 52vw) !important;
    width: max-content !important;
    justify-self: end !important;
    display: flex !important;
    flex-wrap: wrap !important;
    justify-content: flex-end !important;
    align-items: flex-start !important;
    gap: 4px !important;
    overflow: visible !important;
    position: relative !important;
    z-index: 20 !important;
}
body[data-route^="Form/Task"] .page-head .standard-actions,
body[data-route^="Form/Task"] .page-head .custom-actions {
    min-width: 0 !important;
    max-width: 100% !important;
    display: flex !important;
    flex-wrap: wrap !important;
    justify-content: flex-end !important;
    gap: 4px !important;
}
body[data-route^="Form/Task"] .page-head .page-actions .btn,
body[data-route^="Form/Task"] .page-head .standard-actions .btn,
body[data-route^="Form/Task"] .page-head .custom-actions .btn {
    flex: 0 0 auto !important;
    max-width: 190px !important;
    overflow: hidden !important;
    text-overflow: ellipsis !important;
    white-space: nowrap !important;
}
@media (max-width: 1200px) {
    body[data-route^="Form/Task"] .page-head .page-head-content {
        grid-template-columns: minmax(0, 1fr) !important;
        grid-template-areas: "title" "actions" !important;
    }
    body[data-route^="Form/Task"] .page-head .page-actions {
        justify-self: stretch !important;
        width: 100% !important;
        max-width: 100% !important;
        min-width: 0 !important;
        justify-content: flex-start !important;
    }
    body[data-route^="Form/Task"] .page-head .standard-actions,
    body[data-route^="Form/Task"] .page-head .custom-actions {
        justify-content: flex-start !important;
    }
}
`;
        document.head.appendChild(style);
    }

    var wrapper = document.querySelector('body[data-route^="Form/Task"] .page-head');
    if (!wrapper) return;

    var titleText = wrapper.querySelector('.title-text');
    if (titleText) {
        var fullText = (titleText.textContent || '').trim();
        if (fullText) titleText.setAttribute('title', fullText);
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
            $hasV2 = $existing.data.script -match 'task_header_buttons_layout_v2'
            $hasGrid = $existing.data.script -match 'grid-template-areas: "title actions"'
            Write-Host "Has v2 function: $(if($hasV2){'Yes'}else{'No'})"
            Write-Host "Has reserved button grid: $(if($hasGrid){'Yes'}else{'No'})"
            if ($hasV2 -and $hasGrid) { Write-Host "Status: fixed" -ForegroundColor Green } else { Write-Host "Status: needs deploy" -ForegroundColor Yellow }
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
        $backupPath = Join-Path $PSScriptRoot ("_backup_Task_Header_Long_Subject_Fix_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".js")
        $existing.data.script | Set-Content -Path $backupPath -Encoding UTF8
        Write-Host "Backup: $backupPath" -ForegroundColor Green
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $ScriptName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 20 | Out-Null
        Write-Host "Updated existing Client Script" -ForegroundColor Green
    } else {
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 20 | Out-Null
        Write-Host "Created Client Script" -ForegroundColor Green
    }

    Write-Host "Task header layout v2 deployed" -ForegroundColor Green
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    throw
}
