#Requires -Version 5.1
<#
.SYNOPSIS
    Fix Task form header: clamp long subject to 2 lines, keep buttons visible.
.DESCRIPTION
    Updates Task-Header Long Subject Fix client script to:
    - Clamp subject text to 2 lines maximum on desktop
    - Keep action buttons fixed on the right, always visible
    - Show full subject as tooltip on hover
    - Prevent long subject from pushing buttons off-screen
.PARAMETER Mode
    Check  — report current state without making changes (default)
    Deploy — update the script (idempotent)
.PARAMETER Target
    test — deploy to https://test.erpnext.am (default)
    main — deploy to https://erpnext.am
#>
param(
    [ValidateSet("Check","Deploy")]
    [string]$Mode = "Check",
    
    [ValidateSet("test","main")]
    [string]$Target = "test"
)

Set-StrictMode -Off

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config     = Get-Content $ConfigPath -Raw
$ApiKey     = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec     = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value

$BaseUrl = if ($Target -eq "test") { "https://test.erpnext.am" } else { "https://erpnext.am" }
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

function Enc ([string]$s) { [uri]::EscapeDataString($s) }

Write-Host "=== Fix Task Subject Desktop Layout ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

$ScriptName = "Task-Header Long Subject Fix"

$NewScript = @'
frappe.ui.form.on('Task', {
    refresh: function(frm) {
        task_header_subject_clamp_fix();
    }
});

function task_header_subject_clamp_fix() {
    if (document.getElementById('task-header-subject-clamp-fix')) return;
    var style = document.createElement('style');
    style.id = 'task-header-subject-clamp-fix';
    style.textContent = `
/* Desktop: ensure page head content wraps properly */
body[data-route^="Form/Task"] .page-head .container,
body[data-route^="Form/Task"] .page-head .container-fluid,
body[data-route^="Form/Task"] .page-head .page-head-content {
    min-width: 0 !important;
}

/* Flex layout: title area + buttons */
body[data-route^="Form/Task"] .page-head .page-head-content {
    display: flex !important;
    align-items: flex-start !important;
    gap: 12px !important;
    flex-wrap: wrap !important;
}

/* Title area: flexible, can shrink */
body[data-route^="Form/Task"] .page-head .title-area {
    min-width: 0 !important;
    flex: 1 1 auto !important;
    max-width: 100% !important;
    overflow: hidden !important;
}

/* Subject text: clamp to 2 lines, show ellipsis */
body[data-route^="Form/Task"] .page-head .title-text,
body[data-route^="Form/Task"] .page-head .title-text a,
body[data-route^="Form/Task"] .page-head .title-text span,
body[data-route^="Form/Task"] .page-head h3 {
    display: -webkit-box !important;
    -webkit-line-clamp: 2 !important;
    -webkit-box-orient: vertical !important;
    overflow: hidden !important;
    text-overflow: ellipsis !important;
    word-break: break-word !important;
    line-height: 1.3 !important;
    max-height: 2.6em !important;
}

/* Buttons: fixed on the right, always visible */
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

/* Add full subject as title attribute for tooltip */
body[data-route^="Form/Task"] .page-head .title-text {
    cursor: help !important;
}
`;
    document.head.appendChild(style);
    
    // Add full subject as tooltip
    setTimeout(function() {
        var titleText = document.querySelector('body[data-route^="Form/Task"] .page-head .title-text');
        if (titleText && !titleText.hasAttribute('title')) {
            var fullText = titleText.textContent.trim();
            if (fullText) {
                titleText.setAttribute('title', fullText);
            }
        }
    }, 500);
}
'@

try {
    $existing = $null
    try {
        $existing = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $ScriptName)?fields=[`"name`",`"script`"]" -Headers $Headers -Method Get -TimeoutSec 30
    } catch {
        # Script doesn't exist yet
    }
    
    if ($Mode -eq "Check") {
        Write-Host "`nCurrent state:" -ForegroundColor Cyan
        if ($existing) {
            $hasClamp = $existing.data.script -match '-webkit-line-clamp'
            Write-Host "  Script exists: Yes" -ForegroundColor Green
            Write-Host "  Script length: $($existing.data.script.Length) chars"
            Write-Host "  Has 2-line clamp: $(if($hasClamp){'Yes'}else{'No'})" -ForegroundColor $(if($hasClamp){'Green'}else{'Yellow'})
            
            if (-not $hasClamp) {
                Write-Host "`nRecommendation: Run with -Mode Deploy to apply fix" -ForegroundColor Yellow
            } else {
                Write-Host "`nNo changes needed - 2-line clamp already present" -ForegroundColor Green
            }
        } else {
            Write-Host "  Script exists: No" -ForegroundColor Yellow
            Write-Host "`nRecommendation: Run with -Mode Deploy to create script" -ForegroundColor Yellow
        }
        
        return
    }
    
    # Deploy mode
    Write-Host "`nApplying Task subject desktop layout fix..." -ForegroundColor Cyan
    
    $body = @{
        doctype = "Client Script"
        name = $ScriptName
        dt = "Task"
        view = "Form"
        enabled = 1
        script = $NewScript
    } | ConvertTo-Json -Depth 10 -Compress
    
    if ($existing) {
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $ScriptName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
        Write-Host "  Updated existing script" -ForegroundColor Green
    } else {
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
        Write-Host "  Created new script" -ForegroundColor Green
    }
    
    Write-Host "`nDone! Task form header will now:" -ForegroundColor Green
    Write-Host "  - Clamp subject to 2 lines maximum" -ForegroundColor White
    Write-Host "  - Keep action buttons always visible on the right" -ForegroundColor White
    Write-Host "  - Show full subject as tooltip on hover" -ForegroundColor White
    Write-Host "  - Prevent buttons from being pushed off-screen" -ForegroundColor White
    
} catch {
    Write-Host "`nERROR: $_" -ForegroundColor Red
    throw
}
