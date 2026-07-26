#Requires -Version 5.1
<#
.SYNOPSIS
    Add assignee display to mobile Task list view.
.DESCRIPTION
    Updates Global-Mobile Back Button List client script to show assignee in each Task row on mobile:
    - Shows person name if assigned to a specific user
    - Shows team/role name if assigned to a team
    - Shows "Unassigned" if no assignment
    Uses small badge below task subject for clean mobile UI.
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

Write-Host "=== Add Task List Mobile Assignee Display ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

$ScriptName = "Global-Mobile Back Button List"

try {
    $existing = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $ScriptName)?fields=[`"name`",`"script`"]" -Headers $Headers -Method Get -TimeoutSec 30
    $currentScript = $existing.data.script
    
    if ($Mode -eq "Check") {
        $hasAssigneeFormatter = $currentScript -match 'custom_assigned_to|custom_team_queue_role|formatters.*assignee'
        
        Write-Host "`nCurrent state:" -ForegroundColor Cyan
        Write-Host "  Script exists: Yes" -ForegroundColor Green
        Write-Host "  Script length: $($currentScript.Length) chars"
        Write-Host "  Has assignee formatter: $(if($hasAssigneeFormatter){'Yes'}else{'No'})" -ForegroundColor $(if($hasAssigneeFormatter){'Green'}else{'Yellow'})
        
        if (-not $hasAssigneeFormatter) {
            Write-Host "`nRecommendation: Run with -Mode Deploy to add assignee display" -ForegroundColor Yellow
        } else {
            Write-Host "`nAssignee display already present" -ForegroundColor Green
        }
        
        return
    }
    
    # Deploy mode: add assignee formatter
    Write-Host "`nAdding mobile assignee display..." -ForegroundColor Cyan
    
    # Find the location to insert the formatter
    # Look for the frappe.listview_settings['Task'] section
    if (-not ($currentScript -match "frappe\.listview_settings\['Task'\]")) {
        Write-Host "  ERROR: Could not find Task listview_settings section" -ForegroundColor Red
        return
    }
    
    # Add formatter after the onload function
    $assigneeFormatter = @'

    // Mobile: add assignee badge formatter
    if (window.innerWidth <= 768) {
        frappe.listview_settings['Task'].formatters = frappe.listview_settings['Task'].formatters || {};
        frappe.listview_settings['Task'].formatters.subject = function(value, df, doc) {
            var assignee = '';
            
            // Check custom_assigned_to first (specific user)
            if (doc.custom_assigned_to) {
                assignee = '<span style="display:inline-block;margin-top:4px;padding:2px 8px;background:#e3f2fd;color:#1976d2;border-radius:3px;font-size:11px;font-weight:500;">👤 ' + frappe.utils.escape_html(doc.custom_assigned_to) + '</span>';
            }
            // Check custom_team_queue_role (team/role)
            else if (doc.custom_team_queue_role) {
                assignee = '<span style="display:inline-block;margin-top:4px;padding:2px 8px;background:#fff3e0;color:#f57c00;border-radius:3px;font-size:11px;font-weight:500;">👥 ' + frappe.utils.escape_html(doc.custom_team_queue_role) + '</span>';
            }
            // Unassigned
            else {
                assignee = '<span style="display:inline-block;margin-top:4px;padding:2px 8px;background:#f5f5f5;color:#757575;border-radius:3px;font-size:11px;font-weight:500;">⚪ Unassigned</span>';
            }
            
            return '<div>' + frappe.utils.escape_html(value || '') + '<br>' + assignee + '</div>';
        };
    }
'@

    # Insert after the onload function closes
    $insertPoint = $currentScript.IndexOf("frappe.listview_settings['Task'].onload = function(listview) {")
    if ($insertPoint -lt 0) {
        Write-Host "  ERROR: Could not find insertion point" -ForegroundColor Red
        return
    }
    
    # Find the closing of the onload function
    $searchFrom = $insertPoint
    $braceCount = 0
    $foundStart = $false
    $insertAfter = -1
    
    for ($i = $searchFrom; $i -lt $currentScript.Length; $i++) {
        $char = $currentScript[$i]
        if ($char -eq '{') {
            $braceCount++
            $foundStart = $true
        } elseif ($char -eq '}' -and $foundStart) {
            $braceCount--
            if ($braceCount -eq 0) {
                # Find the semicolon after this closing brace
                for ($j = $i; $j -lt [Math]::Min($i + 10, $currentScript.Length); $j++) {
                    if ($currentScript[$j] -eq ';') {
                        $insertAfter = $j + 1
                        break
                    }
                }
                break
            }
        }
    }
    
    if ($insertAfter -lt 0) {
        Write-Host "  ERROR: Could not find onload function end" -ForegroundColor Red
        return
    }
    
    # Check if formatter already exists
    if ($currentScript -match 'formatters\.subject.*custom_assigned_to') {
        Write-Host "  Assignee formatter already exists - no change needed" -ForegroundColor Green
        return
    }
    
    # Insert the formatter
    $updatedScript = $currentScript.Substring(0, $insertAfter) + $assigneeFormatter + $currentScript.Substring($insertAfter)
    
    # Update the script
    $body = @{ script = $updatedScript } | ConvertTo-Json -Depth 10 -Compress
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $ScriptName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
    
    Write-Host "`nDone! Mobile Task list will now show:" -ForegroundColor Green
    Write-Host "  👤 Person name (blue badge) - if assigned to user" -ForegroundColor White
    Write-Host "  👥 Team/Role name (orange badge) - if assigned to team" -ForegroundColor White
    Write-Host "  ⚪ Unassigned (gray badge) - if no assignment" -ForegroundColor White
    Write-Host "`nBadge appears below task subject on mobile." -ForegroundColor White
    
} catch {
    Write-Host "`nERROR: $_" -ForegroundColor Red
    throw
}
