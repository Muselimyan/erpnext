#Requires -Version 5.1
<#
.SYNOPSIS
    Clean up Task assignment field UI presentation.
.DESCRIPTION
    Current assignment fields show ugly help text blocks on desktop and have
    technical labels. This script:
    
    1. Removes description text from assignment fields (cleaner form)
    2. Updates labels to be clearer and self-explanatory
    3. Adds client script to hide fields conditionally for cleaner mobile/desktop UI
    
    Does NOT change assignment workflow/routing logic - UI cleanup only.
.PARAMETER Mode
    Check  — report current state without making changes (default)
    Deploy — apply UI cleanup (idempotent)
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

Write-Host "=== Clean Task Assignment UI ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

# Define field updates
$FieldUpdates = @(
    @{
        name = "Task-custom_assigned_to"
        label = "Assign To: Person"
        description = ""
    },
    @{
        name = "Task-custom_team_queue_role"
        label = "Assign To: Team/Role"
        description = ""
    }
)

if ($Mode -eq "Check") {
    Write-Host "`nChecking current field state..." -ForegroundColor Cyan
    
    foreach ($field in $FieldUpdates) {
        try {
            $current = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Custom%20Field/$(Enc $field.name)?fields=[`"name`",`"label`",`"description`"]" -Headers $Headers -Method Get -TimeoutSec 25).data
            
            $labelMatch = $current.label -eq $field.label
            $descEmpty = [string]::IsNullOrWhiteSpace($current.description)
            
            Write-Host "`n  $($field.name):" -ForegroundColor Cyan
            Write-Host "    Current label: $($current.label)"
            Write-Host "    Target label: $($field.label)"
            Write-Host "    Label OK: $(if($labelMatch){'Yes'}else{'No'})" -ForegroundColor $(if($labelMatch){'Green'}else{'Yellow'})
            Write-Host "    Description empty: $(if($descEmpty){'Yes'}else{'No'})" -ForegroundColor $(if($descEmpty){'Green'}else{'Yellow'})
        } catch {
            Write-Host "`n  $($field.name): Not found" -ForegroundColor Red
        }
    }
    
    # Check if client script has UI cleanup logic
    try {
        $clientScript = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc 'Task-Accept Start')?fields=[`"script`"]" -Headers $Headers -Method Get -TimeoutSec 25).data
        $hasUICleanup = $clientScript.script -match 'frm\.set_df_property.*custom_assigned_to.*description'
        
        Write-Host "`n  Client Script UI cleanup:" -ForegroundColor Cyan
        Write-Host "    Has description hiding: $(if($hasUICleanup){'Yes'}else{'No'})" -ForegroundColor $(if($hasUICleanup){'Green'}else{'Yellow'})
    } catch {
        Write-Host "`n  Client Script: Not found" -ForegroundColor Red
    }
    
    return
}

# Deploy mode
Write-Host "`nApplying assignment UI cleanup..." -ForegroundColor Cyan

# Step 1: Update Custom Field metadata
Write-Host "`nStep 1: Updating Custom Field labels and descriptions" -ForegroundColor Cyan
foreach ($field in $FieldUpdates) {
    $body = @{
        label = $field.label
        description = $field.description
    } | ConvertTo-Json -Compress
    
    try {
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/Custom%20Field/$(Enc $field.name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
        Write-Host "  Updated: $($field.name)" -ForegroundColor Green
    } catch {
        Write-Host "  ERROR updating $($field.name): $_" -ForegroundColor Red
    }
}

# Step 2: Add client script logic to hide descriptions and improve presentation
Write-Host "`nStep 2: Adding client script UI enhancements" -ForegroundColor Cyan

$clientScriptAddition = @'

        // Assignment UI cleanup: hide descriptions, improve presentation
        frm.set_df_property("custom_assigned_to", "description", "");
        frm.set_df_property("custom_team_queue_role", "description", "");
        
        // Show placeholder text for better UX
        if (frm.fields_dict.custom_assigned_to && frm.fields_dict.custom_assigned_to.$input) {
            frm.fields_dict.custom_assigned_to.$input.attr("placeholder", "Select a person to assign this task");
        }
        if (frm.fields_dict.custom_team_queue_role && frm.fields_dict.custom_team_queue_role.$input) {
            frm.fields_dict.custom_team_queue_role.$input.attr("placeholder", "Select a team/role for team queue");
        }
        
        // Hide assignment fields after task is accepted (cleaner mobile UI)
        if (frm.doc.custom_accepted_by && frm.doc.custom_accepted_by === frappe.session.user) {
            if (window.innerWidth <= 768) {
                frm.set_df_property("custom_assigned_to", "hidden", 1);
                frm.set_df_property("custom_team_queue_role", "hidden", 1);
            }
        }
'@

try {
    $clientScript = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc 'Task-Accept Start')?fields=[`"name`",`"script`"]" -Headers $Headers -Method Get -TimeoutSec 30).data
    $currentScript = $clientScript.script
    
    # Check if already added
    if ($currentScript -match 'Assignment UI cleanup') {
        Write-Host "  Client script UI cleanup already present" -ForegroundColor Green
    } else {
        # Find insertion point - after the field hiding section
        $insertMarker = "        frm.toggle_display(`"custom_is_team_queue_task`", false);"
        
        if ($currentScript.Contains($insertMarker)) {
            $insertPos = $currentScript.IndexOf($insertMarker) + $insertMarker.Length
            $updatedScript = $currentScript.Substring(0, $insertPos) + "`r`n" + $clientScriptAddition + $currentScript.Substring($insertPos)
            
            $body = @{ script = $updatedScript } | ConvertTo-Json -Depth 10 -Compress
            Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc 'Task-Accept Start')" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
            
            Write-Host "  Added UI cleanup logic to client script" -ForegroundColor Green
        } else {
            Write-Host "  WARNING: Could not find insertion point in client script" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "  ERROR updating client script: $_" -ForegroundColor Red
}

Write-Host "`nDone! Assignment fields now have:" -ForegroundColor Green
Write-Host "  - Cleaner labels: 'Assign To: Person' and 'Assign To: Team/Role'" -ForegroundColor White
Write-Host "  - No description text blocks (cleaner desktop form)" -ForegroundColor White
Write-Host "  - Placeholder text for better UX" -ForegroundColor White
Write-Host "  - Hidden on mobile after task acceptance (cleaner mobile)" -ForegroundColor White
Write-Host "`nWorkflow/routing logic unchanged - UI cleanup only." -ForegroundColor White
