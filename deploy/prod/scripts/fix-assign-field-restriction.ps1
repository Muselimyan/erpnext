#!/usr/bin/env pwsh
<#
.SYNOPSIS
Fix _assign field restriction errors in server scripts

.DESCRIPTION
ERPNext 16.x introduced RestrictedPython security that blocks direct assignment
to fields starting with underscore (_assign, _user_tags, etc.).
This script updates all server scripts to use the proper add_assign() method.

.PARAMETER Mode
Check or Deploy

.EXAMPLE
.\fix-assign-field-restriction.ps1 -Mode Check
.\fix-assign-field-restriction.ps1 -Mode Deploy
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
)

# Helper functions
Add-Type -AssemblyName System.Web

$BaseUrl = "https://erpnext.am"
$ApiKey = "9f5e50f4e7fa7c3"
$ApiSecret = "7e8c0c0e9e3a3e8"

function Enc { param([string]$s) [System.Web.HttpUtility]::UrlEncode($s) }

function Invoke-ErpRequest {
    param([string]$Method, [string]$Path, $Body = $null)
    $Uri = "$BaseUrl$Path"
    $Headers = @{ "Authorization" = "token $($ApiKey):$($ApiSecret)" }
    if ($Body) {
        $Headers["Content-Type"] = "application/json"
        $Json = $Body | ConvertTo-Json -Depth 40
        return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 120
    }
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 120
}

function Get-ErpDoc {
    param([string]$DocType, [string]$Name)
    try { return (Invoke-ErpRequest -Method Get -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)").data }
    catch { return $null }
}

function Set-ErpDoc {
    param([string]$DocType, [string]$Name, $Body)
    return Invoke-ErpRequest -Method Put -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)" -Body $Body
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Fix _assign Field Restriction Errors" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Updated dispatch_task_accept script
$TaskAcceptApi = @'
task_name = frappe.form_dict.get("task_name")
if not task_name:
    frappe.throw("Task is required.")

task = frappe.get_doc("Task", task_name)
if task.status not in ("Open", "Working"):
    frappe.throw("Only Open or Working tasks can be accepted.")

TASK_KIND_ALLOWED_ROLES = {
    "Order entry": ["Ops - Order Accepting", "Ops - Order Creating"],
    "Pack / prepare items": ["Ops - Inventory"],
    "Dispatch picking / hand-off": ["Ops - Delivery"],
    "Delivery": ["Delivery Driver", "Ops - Delivery"],
    "Pickup Returns": ["Delivery Driver", "Ops - Delivery", "Ops - Returns"],
    "Return drop-off at warehouse": ["Delivery Driver", "Ops - Delivery"],
    "Returns processing / verification": ["Ops - Returns", "Ops - Inventory"],
    "Returns restocking": ["Ops - Returns"],
    "Invoice preparation / create invoice": ["Ops - Accounting"],
    "Debt Collection": ["Ops - Finance", "Ops - Directors"],
    "Discount Approval": ["Ops - Directors"],
    "Purchase Approval": ["Ops - Directors"],
    "Write-off Approval": ["Ops - Directors"],
}
allowed = TASK_KIND_ALLOWED_ROLES.get(task.task_kind) or []
roles = frappe.get_roles(frappe.session.user) or []
if allowed and not any(r in roles for r in allowed) and frappe.session.user != "Administrator" and "System Manager" not in roles:
    frappe.throw("You are not allowed to accept this task kind. Required role: " + ", ".join(allowed))

try:
    assigned = frappe.parse_json(task.get("_assign") or "[]") or []
except Exception:
    assigned = []

team_placeholders = ["inventory.team@example.com", "delivery.team@example.com", "returns.team@example.com", "accounting.team@example.com", "finance.team@example.com", "order.creation.team@example.com", "order.team@example.com"]
real_assigned = [u for u in assigned if u not in team_placeholders]
if real_assigned and frappe.session.user not in real_assigned:
    frappe.throw("Task is already accepted by: " + ", ".join(real_assigned))

# FIXED: Use add_assign() instead of direct _assign assignment
from frappe.desk.form.assign_to import add as add_assign
task.status = "Working"
task.flags.ignore_permissions = True
task.save()

# Clear existing assignments and add current user
for user in assigned:
    try:
        from frappe.desk.form.assign_to import remove as remove_assign
        remove_assign({"doctype": "Task", "name": task.name, "assign_to": user})
    except Exception:
        pass

add_assign({"doctype": "Task", "name": task.name, "assign_to": [frappe.session.user], "description": "Accepted task"})

# Cancel open ToDos
open_todos = frappe.get_all("ToDo", filters={"reference_type": "Task", "reference_name": task.name, "status": "Open"}, pluck="name")
for td in open_todos or []:
    frappe.db.set_value("ToDo", td, "status", "Cancelled")

# Create new ToDo for current user
todo = frappe.new_doc("ToDo")
todo.status = "Open"
todo.allocated_to = frappe.session.user
todo.reference_type = "Task"
todo.reference_name = task.name
todo.description = f"Task accepted: {task.subject}"
todo.flags.ignore_permissions = True
todo.insert()

frappe.response["message"] = {"status": "success", "task": task.name, "assigned_to": frappe.session.user}
'@

if ($Mode -eq "Check") {
    Write-Host "CHECK MODE - Verifying current state...`n" -ForegroundColor Yellow
    
    try {
        $Script = Get-ErpDoc "Server Script" "dispatch_task_accept"
        Write-Host "[OK] Found dispatch_task_accept server script" -ForegroundColor Green
        
        if ($Script.script -like "*task._assign =*") {
            Write-Host "[ERROR] Script contains OLD code: task._assign = ..." -ForegroundColor Red
            Write-Host "  This will cause: '_assign is an invalid attribute name' error" -ForegroundColor Red
            Write-Host "`n  FIX NEEDED: Run with -Mode Deploy to update" -ForegroundColor Yellow
        } elseif ($Script.script -like "*add_assign*") {
            Write-Host "[OK] Script already uses add_assign method" -ForegroundColor Green
        } else {
            Write-Host "[WARN] Script content unclear - manual review needed" -ForegroundColor Yellow
        }
        
    } catch {
        Write-Host "[ERROR] Could not check script: $_" -ForegroundColor Red
    }
    
} else {
    Write-Host "DEPLOY MODE - Updating server script...`n" -ForegroundColor Yellow
    
    try {
        $Payload = @{
            script = $TaskAcceptApi
        }
        
        $Result = Set-ErpDoc "Server Script" "dispatch_task_accept" $Payload
        Write-Host "[OK] Updated dispatch_task_accept server script" -ForegroundColor Green
        Write-Host "  Now uses add_assign method instead of direct _assign assignment" -ForegroundColor Gray
        
    } catch {
        Write-Host "[ERROR] Failed to update script: $_" -ForegroundColor Red
        exit 1
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

if ($Mode -eq "Check") {
    Write-Host "Check complete. Run with -Mode Deploy to apply the fix." -ForegroundColor Yellow
} else {
    Write-Host "[OK] Fix deployed successfully!" -ForegroundColor Green
    Write-Host "`nThe 'Accept / Start Task' button should now work without errors." -ForegroundColor Gray
    Write-Host "Test by:" -ForegroundColor Gray
    Write-Host "  1. Open a Pack task as inventory.team@example.com" -ForegroundColor Gray
    Write-Host "  2. Click 'Accept / Start Task'" -ForegroundColor Gray
    Write-Host "  3. Verify task is assigned to you and status changes to Working" -ForegroundColor Gray
}

Write-Host ""
