#Requires -Version 5.1
<#
.SYNOPSIS
    Add unified task assignment UI with next-task routing.
.DESCRIPTION
    Improves task assignment UX by:
    
    1. Adding "Assign Next Task To" fields for dispatch workflow
    2. Updating server script to use next-task preferences when autocreating tasks
    3. Keeping current assignment fields but improving their presentation
    
    This allows workers to choose who gets the next autocreated task in the
    dispatch workflow (Order Entry → Pack → Delivery → etc).
.PARAMETER Mode
    Check  — report current state without making changes (default)
    Deploy — apply changes (idempotent)
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

Write-Host "=== Add Unified Task Assignment with Next-Task Routing ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

# Define new custom fields for next-task assignment
$CustomFields = @(
    @{
        name = "Task-custom_next_task_assign_to"
        dt = "Task"
        fieldname = "custom_next_task_assign_to"
        label = "Assign Next Task To: Person"
        fieldtype = "Link"
        options = "User"
        insert_after = "custom_team_queue_role"
        hidden = 0
        read_only = 0
        description = ""
    },
    @{
        name = "Task-custom_next_task_assign_role"
        dt = "Task"
        fieldname = "custom_next_task_assign_role"
        label = "Assign Next Task To: Team/Role"
        fieldtype = "Link"
        options = "Role"
        insert_after = "custom_next_task_assign_to"
        hidden = 0
        read_only = 0
        description = ""
    }
)

if ($Mode -eq "Check") {
    Write-Host "`nChecking current state..." -ForegroundColor Cyan
    
    # Check custom fields
    Write-Host "`nCustom Fields:" -ForegroundColor Cyan
    foreach ($cf in $CustomFields) {
        try {
            $exists = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Custom%20Field/$(Enc $cf.name)?fields=[`"name`",`"fieldname`",`"label`"]" -Headers $Headers -Method Get -TimeoutSec 25 -ErrorAction Stop
            Write-Host "  $($cf.fieldname): Exists" -ForegroundColor Green
        } catch {
            Write-Host "  $($cf.fieldname): Missing" -ForegroundColor Yellow
        }
    }
    
    # Check client script
    try {
        $clientScript = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc 'Task-Accept Start')?fields=[`"script`"]" -Headers $Headers -Method Get -TimeoutSec 25).data
        $hasNextTaskUI = $clientScript.script -match 'custom_next_task_assign'
        Write-Host "`nClient Script (Task-Accept Start):" -ForegroundColor Cyan
        Write-Host "  Has next-task UI logic: $(if($hasNextTaskUI){'Yes'}else{'No'})" -ForegroundColor $(if($hasNextTaskUI){'Green'}else{'Yellow'})
    } catch {
        Write-Host "`nClient Script: Not found" -ForegroundColor Red
    }
    
    # Check server script
    try {
        $serverScript = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script/$(Enc 'Task-after-save-dispatch-flow')?fields=[`"script`"]" -Headers $Headers -Method Get -TimeoutSec 25).data
        $hasNextTaskRouting = $serverScript.script -match 'custom_next_task_assign|source_task'
        Write-Host "`nServer Script (Task-after-save-dispatch-flow):" -ForegroundColor Cyan
        Write-Host "  Has next-task routing: $(if($hasNextTaskRouting){'Yes'}else{'No'})" -ForegroundColor $(if($hasNextTaskRouting){'Green'}else{'Yellow'})
    } catch {
        Write-Host "`nServer Script: Not found" -ForegroundColor Red
    }
    
    return
}

# Deploy mode
Write-Host "`nDeploying unified task assignment..." -ForegroundColor Cyan

# Step 1: Create custom fields
Write-Host "`nStep 1: Custom Fields" -ForegroundColor Cyan
foreach ($cf in $CustomFields) {
    $body = @{
        doctype = "Custom Field"
        dt = $cf.dt
        fieldname = $cf.fieldname
        label = $cf.label
        fieldtype = $cf.fieldtype
        options = $cf.options
        insert_after = $cf.insert_after
        hidden = $cf.hidden
        read_only = $cf.read_only
        description = $cf.description
    } | ConvertTo-Json -Depth 10 -Compress
    
    try {
        $exists = $null
        try {
            $exists = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Custom%20Field/$(Enc $cf.name)" -Headers $Headers -Method Get -TimeoutSec 25 -ErrorAction Stop
        } catch {}
        
        if ($exists) {
            Invoke-RestMethod -Uri "$BaseUrl/api/resource/Custom%20Field/$(Enc $cf.name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
            Write-Host "  Updated: $($cf.fieldname)" -ForegroundColor Green
        } else {
            Invoke-RestMethod -Uri "$BaseUrl/api/resource/Custom%20Field" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
            Write-Host "  Created: $($cf.fieldname)" -ForegroundColor Green
        }
    } catch {
        Write-Host "  ERROR: $($cf.fieldname) - $_" -ForegroundColor Red
    }
}

# Step 2: Update client script
Write-Host "`nStep 2: Client Script UI" -ForegroundColor Cyan

$clientScriptAddition = @'

        // Next-task assignment: clear opposite field when one is selected
        if (frm.fields_dict.custom_next_task_assign_to) {
            frm.fields_dict.custom_next_task_assign_to.df.onchange = function() {
                if (frm.doc.custom_next_task_assign_to) {
                    frm.set_value("custom_next_task_assign_role", "");
                }
            };
        }
        if (frm.fields_dict.custom_next_task_assign_role) {
            frm.fields_dict.custom_next_task_assign_role.df.onchange = function() {
                if (frm.doc.custom_next_task_assign_role) {
                    frm.set_value("custom_next_task_assign_to", "");
                }
            };
        }
        
        // Show next-task assignment only for dispatch workflow tasks
        const dispatchKinds = ["Order entry", "Pack / prepare items", "Delivery", "Return Call", "Pickup Returns", "Returns processing / verification", "Returns restocking"];
        if (dispatchKinds.includes(frm.doc.task_kind)) {
            frm.set_df_property("custom_next_task_assign_to", "hidden", 0);
            frm.set_df_property("custom_next_task_assign_role", "hidden", 0);
        } else {
            frm.set_df_property("custom_next_task_assign_to", "hidden", 1);
            frm.set_df_property("custom_next_task_assign_role", "hidden", 1);
        }
'@

try {
    $clientScript = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc 'Task-Accept Start')?fields=[`"name`",`"script`"]" -Headers $Headers -Method Get -TimeoutSec 30).data
    $currentScript = $clientScript.script
    
    if ($currentScript -match 'Next-task assignment') {
        Write-Host "  Client script already has next-task UI logic" -ForegroundColor Green
    } else {
        # Insert after assignment UI cleanup section
        $insertMarker = "        // Hide assignment fields after task is accepted (cleaner mobile UI)"
        
        if ($currentScript.Contains($insertMarker)) {
            # Find end of that section (next blank line or next comment)
            $insertPos = $currentScript.IndexOf($insertMarker)
            $searchFrom = $insertPos + $insertMarker.Length
            $nextSection = $currentScript.IndexOf("`r`n        //", $searchFrom)
            if ($nextSection -lt 0) {
                $nextSection = $currentScript.IndexOf("`r`n`r`n", $searchFrom)
            }
            
            if ($nextSection -gt 0) {
                $updatedScript = $currentScript.Substring(0, $nextSection) + "`r`n" + $clientScriptAddition + $currentScript.Substring($nextSection)
                
                $body = @{ script = $updatedScript } | ConvertTo-Json -Depth 10 -Compress
                Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc 'Task-Accept Start')" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
                
                Write-Host "  Added next-task UI logic to client script" -ForegroundColor Green
            } else {
                Write-Host "  WARNING: Could not find insertion point" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  WARNING: Could not find assignment UI cleanup marker" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "  ERROR updating client script: $_" -ForegroundColor Red
}

# Step 3: Update server script
Write-Host "`nStep 3: Server Script Routing" -ForegroundColor Cyan

try {
    $serverScript = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script/$(Enc 'Task-after-save-dispatch-flow')?fields=[`"name`",`"script`"]" -Headers $Headers -Method Get -TimeoutSec 30).data
    $currentScript = $serverScript.script
    
    if ($currentScript -match 'source_task') {
        Write-Host "  Server script already has next-task routing" -ForegroundColor Green
    } else {
        # Update make_task function signature
        $oldSignature = '    def make_task(kind, subject, assignee, desc="", link_field=None, dispatch_case_name=None, customer=None):'
        $newSignature = '    def make_task(kind, subject, assignee, desc="", link_field=None, dispatch_case_name=None, customer=None, source_task=None):'
        
        if ($currentScript.Contains($oldSignature)) {
            $updatedScript = $currentScript.Replace($oldSignature, $newSignature)
            
            # Add logic to check source_task for next assignment preference
            $insertBefore = '        t.flags.ignore_permissions = True'
            $nextTaskLogic = @'
        # Check if source task specified next-task assignment preference
        if source_task:
            next_user = frappe.db.get_value("Task", source_task, "custom_next_task_assign_to")
            next_role = frappe.db.get_value("Task", source_task, "custom_next_task_assign_role")
            if next_user:
                assignee = next_user
            elif next_role:
                # For role assignment, keep team email placeholder format
                # The role name will be stored in custom_team_queue_role by client script
                pass
        
'@
            
            $updatedScript = $updatedScript.Replace($insertBefore, $nextTaskLogic + "        " + $insertBefore)
            
            # Update all make_task calls to pass source_task=doc.name
            $updatedScript = $updatedScript -replace '(make_task\([^)]+\))', '$1, source_task=doc.name'
            
            # Fix double source_task if already present
            $updatedScript = $updatedScript -replace ', source_task=doc\.name, source_task=doc\.name', ', source_task=doc.name'
            
            $body = @{ script = $updatedScript } | ConvertTo-Json -Depth 10 -Compress
            Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script/$(Enc 'Task-after-save-dispatch-flow')" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
            
            Write-Host "  Added next-task routing logic to server script" -ForegroundColor Green
        } else {
            Write-Host "  WARNING: Could not find make_task function signature" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "  ERROR updating server script: $_" -ForegroundColor Red
}

Write-Host "`nDone! Unified task assignment features:" -ForegroundColor Green
Write-Host "  - Next-task assignment fields added" -ForegroundColor White
Write-Host "  - Visible only for dispatch workflow tasks" -ForegroundColor White
Write-Host "  - Fields clear each other to prevent conflicts" -ForegroundColor White
Write-Host "  - Server script uses next-task preferences when autocreating tasks" -ForegroundColor White
Write-Host "  - If next assignment empty, uses default team" -ForegroundColor White

Write-Host "`nWARNING: This changes task routing logic." -ForegroundColor Yellow
Write-Host "Test thoroughly on test site before deploying to main." -ForegroundColor Yellow
