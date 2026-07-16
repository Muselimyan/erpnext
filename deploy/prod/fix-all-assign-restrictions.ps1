#!/usr/bin/env pwsh
<#
.SYNOPSIS
Fix all _assign field restriction errors in server scripts (ERPNext 16.x compatibility)

.DESCRIPTION
ERPNext 16.x introduced RestrictedPython security that blocks direct assignment
to fields starting with underscore (_assign, _user_tags, etc.).

This script updates ALL affected server scripts to use proper frappe.share.add() 
or add_assign() methods instead of direct _assign assignment.

Affected scripts:
- dispatch_task_accept (API)
- Dispatch-Case-after-save (creates discount approval tasks)
- Dispatch-Case-before-submit (creates pack tasks)
- Task-after-save-dispatch-flow (creates delivery/returns/invoice tasks)

.PARAMETER Mode
Check or Deploy

.EXAMPLE
.\fix-all-assign-restrictions.ps1 -Mode Check
.\fix-all-assign-restrictions.ps1 -Mode Deploy
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
)

# Helper functions
Add-Type -AssemblyName System.Web

# Load credentials from export.ps1
$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSecret = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value

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
Write-Host "Fix All _assign Restriction Errors" -ForegroundColor Cyan
Write-Host "ERPNext 16.x Compatibility Update" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ============================================================================
# 1. dispatch_task_accept (API Script)
# ============================================================================
$Script1_Content = @'
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

# FIXED: Use frappe.share.add instead of direct _assign
task.status = "Working"
task.flags.ignore_permissions = True
task.save()

# Clear existing assignments
for user in assigned:
    try:
        frappe.share.remove("Task", task.name, user)
    except Exception:
        pass

# Add current user
frappe.share.add("Task", task.name, frappe.session.user, write=1, share=0, notify=0)

# Cancel open ToDos
open_todos = frappe.get_all("ToDo", filters={"reference_type": "Task", "reference_name": task.name, "status": "Open"}, pluck="name")
for td in open_todos or []:
    frappe.db.set_value("ToDo", td, "status", "Cancelled")

# Create new ToDo
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

# ============================================================================
# 2. Dispatch-Case-after-save (creates discount approval tasks)
# ============================================================================
$Script2_Content = @'
import json
if doc.status != "Draft" or not doc.case_items:
    pass
else:
    has_discount = any((r.discount_pct or 0) > 0 for r in doc.case_items)
    if has_discount and not doc.discount_approval_task:
        disc_lines = "\n".join(f"- {r.item_code}: {r.discount_pct}%" for r in doc.case_items if (r.discount_pct or 0) > 0)
        t = frappe.get_doc({
            "doctype": "Task",
            "subject": f"Discount Approval: {doc.name} — {doc.customer}",
            "task_kind": "Discount Approval",
            "task_access_policy": "Discount Approval",
            "dispatch_case": doc.name,
            "customer": doc.customer,
            "description": f"Review and approve or reject discounts.\n\n{disc_lines}",
        })
        t.flags.ignore_permissions = True
        t.insert()
        frappe.db.set_value("Dispatch Case", doc.name, "discount_approval_task", t.name)
        # FIXED: Use frappe.share.add instead of _assign
        frappe.share.add("Task", t.name, "directors.team@example.com", write=1, share=0, notify=1)
'@

# ============================================================================
# 3. Dispatch-Case-before-submit (creates pack tasks)
# ============================================================================
$Script3_Content = @'
import json
if not doc.case_items:
    frappe.throw("Add at least one item before submitting.")
if doc.status not in ("Draft", "Confirmed"):
    frappe.throw("Cannot submit a Dispatch Case in status: " + doc.status)
if doc.status == "Draft":
    doc.status = "Confirmed"
existing_pack = frappe.db.exists("Task", {"dispatch_case": doc.name, "task_kind": "Pack / prepare items", "status": ["not in", ["Completed", "Cancelled"]]})
if not existing_pack:
    items_txt = "\n".join(f"- {r.item_code} x{r.dispatched_qty}" for r in doc.case_items)
    t = frappe.get_doc({
        "doctype": "Task",
        "subject": f"Pack: {doc.name} — {doc.customer}",
        "task_kind": "Pack / prepare items",
        "task_access_policy": "Pack / prepare items",
        "dispatch_case": doc.name,
        "customer": doc.customer,
        "description": f"Pack for delivery to: {doc.customer}\nDest: {doc.client_location_warehouse}\n\n{items_txt}",
    })
    t.flags.ignore_permissions = True
    t.insert()
    doc.pack_task = t.name
    # FIXED: Use frappe.share.add instead of _assign
    frappe.share.add("Task", t.name, "inventory.team@example.com", write=1, share=0, notify=1)
'@

# ============================================================================
# 4. Task-after-save-dispatch-flow (creates delivery/returns/invoice tasks)
# ============================================================================
$Script4_Content = @'
import json
import frappe
from frappe.utils import nowdate

COMPANY = "Muselimyan"
FINANCE_TEAM = "finance.team@example.com"

if not doc.dispatch_case or doc.task_kind not in ("Pack / prepare items", "Delivery", "Pickup Returns", "Returns processing / verification", "Debt Collection"):
    pass
else:
    before = doc.get_doc_before_save()
    before_status = before.status if before else None
    is_completing = (doc.status == "Completed" and before_status != "Completed")
    case = frappe.get_doc("Dispatch Case", doc.dispatch_case)

    def get_returned_items(c):
        return [(r.item_code, r.returned_qty, r.serial_no, r.batch_no) for r in (c.case_items or []) if (r.returned_qty or 0) > 0]

    def make_task(kind, subject, assignee, desc="", link_field=None):
        existing = frappe.db.exists("Task", {"dispatch_case": doc.dispatch_case, "task_kind": kind, "status": ["not in", ["Completed", "Cancelled"]]})
        if existing:
            return existing
        t = frappe.get_doc({
            "doctype": "Task", "subject": subject, "task_kind": kind, "task_access_policy": kind,
            "dispatch_case": doc.dispatch_case, "customer": case.customer, "description": desc,
        })
        t.flags.ignore_permissions = True
        t.insert()
        if link_field:
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, link_field, t.name)
        # FIXED: Use frappe.share.add instead of _assign
        frappe.share.add("Task", t.name, assignee, write=1, share=0, notify=1)
        return t.name

    def create_invoice(c):
        items_rows = []
        for r in (c.case_items or []):
            qty = r.used_qty if (r.used_qty or 0) > 0 else r.dispatched_qty
            if not qty:
                continue
            rate = (r.unit_price or 0) * (1 - (r.discount_pct or 0) / 100)
            items_rows.append({"item_code": r.item_code, "qty": qty, "rate": rate})
        if not items_rows:
            return
        si = frappe.get_doc({"doctype": "Sales Invoice", "customer": c.customer, "company": COMPANY, "update_stock": 0, "items": items_rows})
        si.flags.ignore_permissions = True
        si.insert()
        frappe.db.set_value("Dispatch Case", c.name, "sales_invoice", si.name)
        return si.name

    def update_debt_collection(customer, invoice_name):
        existing_task = frappe.db.get_value("Task", {"customer": customer, "task_kind": "Debt Collection", "status": ["not in", ["Completed", "Cancelled"]]}, "name")
        if existing_task:
            task_doc = frappe.get_doc("Task", existing_task)
            invoices = frappe.get_all("Sales Invoice", filters={"customer": customer, "docstatus": 1, "outstanding_amount": [">", 0]}, fields=["name", "posting_date", "grand_total", "outstanding_amount"])
            task_doc.open_invoices = []
            total_out = 0
            for inv in invoices:
                task_doc.append("open_invoices", {"invoice": inv.name, "posting_date": inv.posting_date, "grand_total": inv.grand_total, "outstanding": inv.outstanding_amount})
                total_out += inv.outstanding_amount
            task_doc.total_outstanding = total_out
            task_doc.flags.ignore_permissions = True
            task_doc.save()
        else:
            invoices = frappe.get_all("Sales Invoice", filters={"customer": customer, "docstatus": 1, "outstanding_amount": [">", 0]}, fields=["name", "posting_date", "grand_total", "outstanding_amount"])
            if not invoices:
                return
            total_out = sum(i.outstanding_amount for i in invoices)
            inv_row = [{"invoice": i.name, "posting_date": i.posting_date, "grand_total": i.grand_total, "outstanding": i.outstanding_amount} for i in invoices]
            t = frappe.get_doc({
                "doctype": "Task", "subject": f"Debt Collection: {customer}",
                "task_kind": "Debt Collection", "task_access_policy": "Debt Collection",
                "customer": customer, "total_outstanding": total_out,
                "open_invoices": inv_row,
            })
            t.flags.ignore_permissions = True
            t.insert()
            # FIXED: Use frappe.share.add instead of _assign
            frappe.share.add("Task", t.name, FINANCE_TEAM, write=1, share=0, notify=1)

    # Pack task completed
    if is_completing and doc.task_kind == "Pack / prepare items":
        make_task("Delivery", f"Deliver: {doc.dispatch_case}", "delivery.team@example.com", "Deliver items to client location.")

    # Delivery task completed
    if is_completing and doc.task_kind == "Delivery":
        if case.return_expected:
            make_task("Pickup Returns", f"Wait for return call: {doc.dispatch_case}", "returns.team@example.com", "Wait for client to call for pickup.")

    # Pickup Returns task completed
    if is_completing and doc.task_kind == "Pickup Returns":
        make_task("Returns processing / verification", f"Inspect returns: {doc.dispatch_case}", "returns.team@example.com", "Inspect returned items and record quantities.")

    # Returns Inspection completed
    if is_completing and doc.task_kind == "Returns processing / verification":
        returned_items = get_returned_items(case)
        if returned_items:
            make_task("Returns restocking", f"Restock returns: {doc.dispatch_case}", "returns.team@example.com", "Move items from Returns shelf to Main warehouse.")
        invoice_name = create_invoice(case)
        if invoice_name:
            make_task("Invoice preparation / create invoice", f"Invoice: {doc.dispatch_case}", "accounting.team@example.com", f"Review and submit Sales Invoice {invoice_name}.")
            update_debt_collection(case.customer, invoice_name)
'@

# ============================================================================
# Deploy or Check
# ============================================================================

$Scripts = @(
    @{Name="dispatch_task_accept"; Content=$Script1_Content; Type="API"},
    @{Name="Dispatch-Case-after-save"; Content=$Script2_Content; Type="DocType Event"},
    @{Name="Dispatch-Case-before-submit"; Content=$Script3_Content; Type="DocType Event"},
    @{Name="Task-after-save-dispatch-flow"; Content=$Script4_Content; Type="DocType Event"}
)

if ($Mode -eq "Check") {
    Write-Host "CHECK MODE - Verifying current state...`n" -ForegroundColor Yellow
    
    $NeedsFix = 0
    $AlreadyFixed = 0
    $NotFound = 0
    
    foreach ($Script in $Scripts) {
        Write-Host "Checking: $($Script.Name)" -ForegroundColor Cyan
        try {
            $Doc = Get-ErpDoc "Server Script" $Script.Name
            if ($null -eq $Doc) {
                Write-Host "  [WARN] Script not found in ERPNext" -ForegroundColor Yellow
                $NotFound++
            } elseif ($Doc.script -like "*._assign*=*" -or $Doc.script -like "*_assign*=*json*") {
                Write-Host "  [ERROR] Contains OLD code: ._assign = ..." -ForegroundColor Red
                Write-Host "    Will cause: '_assign is an invalid attribute name' error" -ForegroundColor Red
                $NeedsFix++
            } elseif ($Doc.script -like "*frappe.share.add*") {
                Write-Host "  [OK] Already uses frappe.share.add method" -ForegroundColor Green
                $AlreadyFixed++
            } else {
                Write-Host "  [WARN] Cannot determine - manual review needed" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  [ERROR] Could not check: $_" -ForegroundColor Red
        }
        Write-Host ""
    }
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Check Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Scripts needing fix: $NeedsFix" -ForegroundColor $(if ($NeedsFix -gt 0) { "Red" } else { "Green" })
    Write-Host "Already fixed: $AlreadyFixed" -ForegroundColor Green
    Write-Host "Not found: $NotFound" -ForegroundColor $(if ($NotFound -gt 0) { "Yellow" } else { "Gray" })
    
    if ($NeedsFix -gt 0) {
        Write-Host "`n[ACTION NEEDED] Run with -Mode Deploy to fix $NeedsFix script(s)" -ForegroundColor Yellow
    } else {
        Write-Host "`n[OK] All scripts are already fixed or not found" -ForegroundColor Green
    }
    
} else {
    Write-Host "DEPLOY MODE - Updating server scripts...`n" -ForegroundColor Yellow
    
    $Updated = 0
    $Failed = 0
    
    foreach ($Script in $Scripts) {
        Write-Host "Updating: $($Script.Name)" -ForegroundColor Cyan
        try {
            $Payload = @{
                script = $Script.Content
            }
            
            $Result = Set-ErpDoc "Server Script" $Script.Name $Payload
            Write-Host "  [OK] Updated successfully" -ForegroundColor Green
            $Updated++
        } catch {
            Write-Host "  [ERROR] Failed to update: $_" -ForegroundColor Red
            $Failed++
        }
        Write-Host ""
    }
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Deploy Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Successfully updated: $Updated" -ForegroundColor $(if ($Updated -gt 0) { "Green" } else { "Gray" })
    Write-Host "Failed: $Failed" -ForegroundColor $(if ($Failed -gt 0) { "Red" } else { "Gray" })
    
    if ($Updated -gt 0 -and $Failed -eq 0) {
        Write-Host "`n[SUCCESS] All scripts updated!" -ForegroundColor Green
        Write-Host "`nThe following workflows should now work without _assign errors:" -ForegroundColor Gray
        Write-Host "  - Accept / Start Task button" -ForegroundColor Gray
        Write-Host "  - Creating discount approval tasks" -ForegroundColor Gray
        Write-Host "  - Creating pack tasks" -ForegroundColor Gray
        Write-Host "  - Creating delivery/returns/invoice tasks" -ForegroundColor Gray
        Write-Host "`nTest by continuing your surgery case walkthrough Step 3." -ForegroundColor Gray
    } elseif ($Failed -gt 0) {
        Write-Host "`n[PARTIAL] Some scripts failed to update. Check errors above." -ForegroundColor Yellow
    }
}

Write-Host ""
