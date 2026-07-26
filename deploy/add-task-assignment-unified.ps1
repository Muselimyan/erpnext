#Requires -Version 5.1
<#
.SYNOPSIS
    Add unified task assignment UI with next-task routing.
.DESCRIPTION
    Creates a comfortable one-box assignment selector for Task that can assign to:
    - Specific user (person)
    - Team/Role
    
    Also adds "Assign Next Task To" field so user can choose assignment for the
    autocreated next task in the dispatch workflow.
    
    Changes:
    1. Adds/updates Custom Fields:
       - custom_assigned_to label becomes Assign To
       - custom_next_task_assign_to (Link to User, optional)
    
    2. Updates Task-Accept Start client script:
       - Hides deprecated custom_team_queue_role
       - Shows next-task assignment field for dispatch tasks
    
    3. Updates Task-after-save-dispatch-flow server script:
       - Uses custom_next_task_assign_to from source task
       - Falls back to default team placeholder assignment if not specified
.PARAMETER Mode
    Check  — report current state without making changes (default)
    Deploy — create/update fields and scripts (idempotent)
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
$ErrorActionPreference = "Stop"

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config     = Get-Content $ConfigPath -Raw
$ApiKey     = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec     = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value

$BaseUrl = if ($Target -eq "test") { "https://test.erpnext.am" } else { "https://erpnext.am" }
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json"; "User-Agent" = "Mozilla/5.0" }

function Enc ([string]$s) { [uri]::EscapeDataString($s) }
function Invoke-ErpRequest { param([string]$Method, [string]$Path, $Body=$null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 60 -ErrorAction Stop }
    $Json = $Body | ConvertTo-Json -Depth 40
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 60 -ErrorAction Stop
}
function Get-ErpDoc { param([string]$DocType,[string]$Name)
    try { return (Invoke-ErpRequest -Method Get -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)").data } catch { return $null }
}
function Upsert-ErpDoc { param([string]$DocType,[string]$Name,$Body)
    $Existing = Get-ErpDoc $DocType $Name
    if ($null -eq $Existing) { 
        $Body.name=$Name
        $C=(Invoke-ErpRequest -Method Post -Path "/api/resource/$(Enc $DocType)" -Body $Body).data
        return [pscustomobject]@{action="created";name=$C.name} 
    }
    $U=(Invoke-ErpRequest -Method Put -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)" -Body $Body).data
    return [pscustomobject]@{action="updated";name=$U.name}
}

Write-Host "=== Add Unified Task Assignment with Next-Task Routing ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

# Define custom fields for unified assignment
$CustomFields = @(
    @{
        name = "Task-custom_assigned_to"
        dt = "Task"
        fieldname = "custom_assigned_to"
        label = "Assign To"
        fieldtype = "Link"
        options = "User"
        insert_after = "task_kind"
        hidden = 0
        read_only = 0
        in_list_view = 0
        description = ""
    },
    @{
        name = "Task-custom_next_task_assign_to"
        dt = "Task"
        fieldname = "custom_next_task_assign_to"
        label = "Next Task: Assign To"
        fieldtype = "Link"
        options = "User"
        insert_after = "custom_assigned_to"
        hidden = 0
        read_only = 0
        in_list_view = 0
        description = ""
    }
)

if ($Mode -eq "Check") {
    Write-Host "`nChecking current state..." -ForegroundColor Cyan
    
    # Check custom fields
    Write-Host "`nCustom Fields:" -ForegroundColor Cyan
    foreach ($cf in $CustomFields) {
        $exists = Get-ErpDoc "Custom Field" $cf.name
        $status = if ($exists) { "Exists" } else { "Missing" }
        $color = if ($exists) { "Green" } else { "Yellow" }
        Write-Host "  $($cf.fieldname): $status" -ForegroundColor $color
    }
    
    # Check client script
    $clientScript = Get-ErpDoc "Client Script" "Task-Accept Start"
    $hasNextTaskUI = if ($clientScript) { $clientScript.script -match 'custom_next_task_assign' } else { $false }
    Write-Host "`nClient Script (Task-Accept Start):" -ForegroundColor Cyan
    Write-Host "  Exists: $(if($clientScript){'Yes'}else{'No'})" -ForegroundColor $(if($clientScript){'Green'}else{'Red'})
    Write-Host "  Has next-task UI: $(if($hasNextTaskUI){'Yes'}else{'No'})" -ForegroundColor $(if($hasNextTaskUI){'Green'}else{'Yellow'})
    
    # Check server script
    $serverScript = Get-ErpDoc "Server Script" "Task-after-save-dispatch-flow"
    $hasNextTaskLogic = if ($serverScript) { $serverScript.script -match 'custom_next_task_assign' } else { $false }
    Write-Host "`nServer Script (Task-after-save-dispatch-flow):" -ForegroundColor Cyan
    Write-Host "  Exists: $(if($serverScript){'Yes'}else{'No'})" -ForegroundColor $(if($serverScript){'Green'}else{'Red'})
    Write-Host "  Has next-task routing: $(if($hasNextTaskLogic){'Yes'}else{'No'})" -ForegroundColor $(if($hasNextTaskLogic){'Green'}else{'Yellow'})
    
    $allReady = ($CustomFields | ForEach-Object { Get-ErpDoc "Custom Field" $_.name }) -notcontains $null -and $hasNextTaskUI -and $hasNextTaskLogic
    
    if (-not $allReady) {
        Write-Host "`nRecommendation: Run with -Mode Deploy to add unified assignment" -ForegroundColor Yellow
    } else {
        Write-Host "`nAll components present - unified assignment ready" -ForegroundColor Green
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
        in_list_view = $cf.in_list_view
    }
    if ($cf.description) { $body.description = $cf.description }
    
    $result = Upsert-ErpDoc "Custom Field" $cf.name $body
    Write-Host "  $($cf.fieldname): $($result.action)" -ForegroundColor Green
}

# Step 2: Update client script to add next-task assignment UI
Write-Host "`nStep 2: Client Script UI" -ForegroundColor Cyan

$clientScriptAddition = @'

        // Unified assignment UI
        frm.toggle_display("custom_team_queue_role", false);
        frm.set_df_property("custom_assigned_to", "label", "Assign To");
        frm.set_df_property("custom_next_task_assign_to", "label", "Next Task: Assign To");
        
        // Show next-task assignment for dispatch workflow tasks
        const dispatchKinds = ["Order entry", "Pack / prepare items", "Delivery", "Return Call", "Pickup Returns", "Returns processing / verification", "Returns restocking", "Invoice preparation / create invoice", "Discount Approval"];
        if (dispatchKinds.includes(frm.doc.task_kind)) {
            frm.set_df_property("custom_next_task_assign_to", "hidden", 0);
        } else {
            frm.set_df_property("custom_next_task_assign_to", "hidden", 1);
        }
'@

$clientScript = Get-ErpDoc "Client Script" "Task-Accept Start"
if (-not $clientScript) {
    Write-Host "  ERROR: Task-Accept Start client script not found" -ForegroundColor Red
    return
}

$currentClientScript = $clientScript.script

# Check if addition already exists
if ($currentClientScript -match 'custom_next_task_assign') {
    Write-Host "  Next-task UI already present - no change needed" -ForegroundColor Green
} else {
    # Find a good insertion point - after the refresh function starts but before Accept button logic
    # Look for the line with "// Hide sidebar items"
    $insertPoint = $currentClientScript.IndexOf("// Hide sidebar items:")
    if ($insertPoint -lt 0) {
        # Try alternate marker
        $insertPoint = $currentClientScript.IndexOf("frm.toggle_display(`"custom_is_team_queue_task`", false);")
    }
    
    if ($insertPoint -gt 0) {
        $updatedClientScript = $currentClientScript.Substring(0, $insertPoint) + $clientScriptAddition + "`n        " + $currentClientScript.Substring($insertPoint)
        
        $body = @{ script = $updatedClientScript }
        Invoke-ErpRequest -Method Put -Path "/api/resource/Client%20Script/$(Enc 'Task-Accept Start')" -Body $body | Out-Null
        Write-Host "  Added next-task assignment UI" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: Could not find insertion point in client script" -ForegroundColor Yellow
    }
}

# Step 3: Update server script to use next-task assignment
Write-Host "`nStep 3: Server Script Routing" -ForegroundColor Cyan

$serverScript = Get-ErpDoc "Server Script" "Task-after-save-dispatch-flow"
if (-not $serverScript) {
    Write-Host "  ERROR: Task-after-save-dispatch-flow server script not found" -ForegroundColor Red
    return
}

$currentServerScript = $serverScript.script

$updatedServerScript = $currentServerScript
$serverModified = $false

$oldMakeTaskSignature = 'def make_task(kind, subject, assignee, desc="", link_field=None, dispatch_case_name=None, customer=None):'
$newMakeTaskSignature = 'def make_task(kind, subject, assignee, desc="", link_field=None, dispatch_case_name=None, customer=None, source_task=None):'

if ($updatedServerScript.Contains($oldMakeTaskSignature)) {
    $updatedServerScript = $updatedServerScript.Replace($oldMakeTaskSignature, $newMakeTaskSignature)
    $serverModified = $true
}

if ($updatedServerScript -notmatch 'custom_next_task_assign_to') {
    $assigneeCheckOld = '    t.flags.ignore_permissions = True'
    $assigneeCheckNew = @'
        # Check if source task specified next-task assignment
        if source_task:
            next_user = frappe.db.get_value("Task", source_task, "custom_next_task_assign_to")
            if next_user:
                assignee = next_user
        t.custom_assigned_to = assignee
    
        t.flags.ignore_permissions = True
'@
    $assigneeIndex = $updatedServerScript.IndexOf($assigneeCheckOld)
    if ($assigneeIndex -lt 0) {
        Write-Host "  WARNING: Could not find make_task insertion point" -ForegroundColor Yellow
        return
    }
    $updatedServerScript = $updatedServerScript.Substring(0, $assigneeIndex) + $assigneeCheckNew + $updatedServerScript.Substring($assigneeIndex + $assigneeCheckOld.Length)
    $serverModified = $true
}

$beforeCalls = $updatedServerScript
$updatedServerScript = $updatedServerScript.Replace('doc.dispatch_case, case.customer)', 'doc.dispatch_case, case.customer, source_task=doc.name)')
$updatedServerScript = $updatedServerScript.Replace('doc.dispatch_case, case.customer, source_task=doc.name, source_task=doc.name)', 'doc.dispatch_case, case.customer, source_task=doc.name)')
if ($updatedServerScript -ne $beforeCalls) {
    $serverModified = $true
}

if ($serverModified) {
    $body = @{ script = $updatedServerScript }
    Invoke-ErpRequest -Method Put -Path "/api/resource/Server%20Script/$(Enc 'Task-after-save-dispatch-flow')" -Body $body | Out-Null
    Write-Host "  Updated next-task routing logic and make_task call sites" -ForegroundColor Green
} else {
    Write-Host "  Next-task routing already complete - no change needed" -ForegroundColor Green
}

# Step 4: Update accept API to write custom_assigned_to
Write-Host "`nStep 4: Accept API assignment sync" -ForegroundColor Cyan
$acceptScript = Get-ErpDoc "Server Script" "dispatch_task_accept"
if (-not $acceptScript) {
    Write-Host "  ERROR: dispatch_task_accept server script not found" -ForegroundColor Red
} elseif ($acceptScript.script -match 'custom_assigned_to\s*=\s*frappe\.session\.user') {
    Write-Host "  Accept API already sets custom_assigned_to" -ForegroundColor Green
} else {
    $acceptUpdated = $acceptScript.script.Replace('task.custom_accepted_by = frappe.session.user', "task.custom_accepted_by = frappe.session.user`ntask.custom_assigned_to = frappe.session.user")
    $body = @{ script = $acceptUpdated }
    Invoke-ErpRequest -Method Put -Path "/api/resource/Server%20Script/$(Enc 'dispatch_task_accept')" -Body $body | Out-Null
    Write-Host "  Updated accept API to set custom_assigned_to" -ForegroundColor Green
}

Write-Host "`nDone! Unified task assignment is now available:" -ForegroundColor Green
Write-Host "  - Assign current task to a real user OR team placeholder user" -ForegroundColor White
Write-Host "  - Choose assignment for next autocreated task" -ForegroundColor White
Write-Host "  - If next assignment is empty, uses default team placeholder" -ForegroundColor White
Write-Host "`nNext-task field visible only for dispatch workflow tasks." -ForegroundColor White

Write-Host "`nWARNING: This is the highest-risk change." -ForegroundColor Yellow
Write-Host "Test thoroughly on test site before deploying to main." -ForegroundColor Yellow
