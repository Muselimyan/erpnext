$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }

$script = @'
frappe.ui.form.on('Task', {
    refresh: function(frm) {
        task_header_long_subject_fix();
    }
});

function task_header_long_subject_fix() {
    if (document.getElementById('task-header-long-subject-fix')) return;
    var style = document.createElement('style');
    style.id = 'task-header-long-subject-fix';
    style.textContent = `
body[data-route^="Form/Task"] .page-head .container,
body[data-route^="Form/Task"] .page-head .container-fluid,
body[data-route^="Form/Task"] .page-head .page-head-content,
body[data-route^="Form/Task"] .page-head .standard-actions {
    min-width: 0 !important;
}
body[data-route^="Form/Task"] .page-head .page-head-content {
    display: flex !important;
    align-items: flex-start !important;
    gap: 8px !important;
    flex-wrap: nowrap !important;
}
body[data-route^="Form/Task"] .page-head .title-area {
    min-width: 0 !important;
    flex: 1 1 auto !important;
    max-width: none !important;
    overflow: visible !important;
}
body[data-route^="Form/Task"] .page-head .title-text,
body[data-route^="Form/Task"] .page-head .title-text a,
body[data-route^="Form/Task"] .page-head .title-text span,
body[data-route^="Form/Task"] .page-head h3,
body[data-route^="Form/Task"] .page-head .ellipsis {
    white-space: normal !important;
    overflow-wrap: anywhere !important;
    word-break: break-word !important;
    overflow: visible !important;
    text-overflow: clip !important;
    line-height: 1.25 !important;
    max-width: 100% !important;
}
body[data-route^="Form/Task"] .page-head .page-actions,
body[data-route^="Form/Task"] .page-head .standard-actions,
body[data-route^="Form/Task"] .page-head .custom-actions {
    flex: 0 0 auto !important;
    white-space: nowrap !important;
    display: flex !important;
    align-items: flex-start !important;
    justify-content: flex-end !important;
    min-width: max-content !important;
    margin-left: auto !important;
    position: relative !important;
    z-index: 2 !important;
}
body[data-route^="Form/Task"] .page-head .page-actions .btn,
body[data-route^="Form/Task"] .page-head .standard-actions .btn,
body[data-route^="Form/Task"] .page-head .custom-actions .btn {
    flex: 0 0 auto !important;
}
`;
    document.head.appendChild(style);
}
'@

$body = @{
    doctype = "Client Script"
    name = "Task-Header Long Subject Fix"
    dt = "Task"
    view = "Form"
    enabled = 1
    script = $script
} | ConvertTo-Json -Depth 6 -Compress

try {
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc 'Task-Header Long Subject Fix')" -Headers $Headers -Method Get -TimeoutSec 10 | Out-Null
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc 'Task-Header Long Subject Fix')" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
    Write-Host "Updated Task-Header Long Subject Fix." -ForegroundColor Green
} catch {
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
    Write-Host "Created Task-Header Long Subject Fix." -ForegroundColor Green
}
