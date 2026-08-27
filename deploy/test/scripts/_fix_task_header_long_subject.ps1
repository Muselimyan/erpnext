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
        task_subject_field_visibility_fix(frm);
        setTimeout(function() { task_subject_field_visibility_fix(frm); }, 250);
        setTimeout(function() { task_subject_field_visibility_fix(frm); }, 900);
    },
    subject: function(frm) {
        task_subject_field_visibility_fix(frm);
    }
});

function task_subject_field_visibility_fix(frm) {
    try {
        var oldStyle = document.getElementById('task-header-long-subject-fix');
        if (oldStyle) oldStyle.remove();

        if (!document.getElementById('task-subject-field-visibility-fix')) {
            var style = document.createElement('style');
            style.id = 'task-subject-field-visibility-fix';
            style.textContent = `
body[data-route^="Form/Task"] [data-fieldname="subject"],
body[data-route^="Form/Task"] [data-fieldname="subject"] .control-input-wrapper,
body[data-route^="Form/Task"] [data-fieldname="subject"] .control-input {
    display: block !important;
    visibility: visible !important;
}
body[data-route^="Form/Task"] .task-visible-subject-banner {
    display: none !important;
    visibility: hidden !important;
}
`;
            document.head.appendChild(style);
        }

        if (frm && frm.fields_dict && frm.fields_dict.subject) {
            frm.toggle_display('subject', true);
            frm.set_df_property('subject', 'hidden', 0);
        }
        if (frm && frm.wrapper) {
            $(frm.wrapper).find('.task-visible-subject-banner').remove();
            $(frm.wrapper).find('[data-fieldname="subject"]').closest('.frappe-control').show().css({ display: 'block', visibility: 'visible' });
        }
    } catch (e) {}
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
    Write-Host "Updated Task-Header Long Subject Fix with minimal safe subject visibility only." -ForegroundColor Green
} catch {
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
    Write-Host "Created Task-Header Long Subject Fix with minimal safe subject visibility only." -ForegroundColor Green
}
