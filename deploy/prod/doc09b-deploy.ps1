#Requires -Version 5.1
<#
.SYNOPSIS
    Doc 09B — Standard Sale: missing task-automation scripts.
    Implements the two gaps identified in Doc 15:
      Gap 1  Sales Order-after-submit-pack-task          (NEW)
             Auto-creates "Pack / prepare items" task on SO submit when
             discount is not required or already approved.
      Gap 1b Task-before-save-discount-approval-writeback (UPDATE existing)
             Extended: after writing approval back to SO, also creates the
             Pack task when outcome = Approved and SO is submitted.
      Gap 2  Task-before-save-pack-complete-creates-delivery-task (NEW)
             When Pack task is marked Completed, auto-creates "Delivery"
             task for the driver / delivery team.
.PARAMETER Mode
    Check  - report current state without making changes (default)
    Deploy - create / update all scripts (idempotent)
#>
param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
)

Set-StrictMode -Off

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config     = Get-Content $ConfigPath -Raw
$BaseUrl    = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey     = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec     = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers    = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

function Enc([string]$s) { [uri]::EscapeDataString($s) }

function Invoke-ErpRequest {
    param([string]$Method, [string]$Path, $Body = $null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method }
    $Json = $Body | ConvertTo-Json -Depth 30
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json))
}

function Get-ErpDoc {
    param([string]$DocType, [string]$Name)
    try { return (Invoke-ErpRequest -Method Get -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)").data }
    catch { return $null }
}

function Upsert-ErpDoc {
    param([string]$DocType, [string]$Name, $Body)
    $Existing = Get-ErpDoc -DocType $DocType -Name $Name
    if ($null -eq $Existing) {
        $Body.name = $Name
        $C = (Invoke-ErpRequest -Method Post -Path "/api/resource/$(Enc $DocType)" -Body $Body).data
        return [pscustomobject]@{ action = "created"; name = $C.name }
    }
    $U = (Invoke-ErpRequest -Method Put -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)" -Body $Body).data
    return [pscustomobject]@{ action = "updated"; name = $U.name }
}

# ---------------------------------------------------------------------------
# Gap 1 — NEW script: Sales Order-after-submit-pack-task
# Fires: Sales Order > After Submit
# Creates a "Pack / prepare items" task immediately when discount is not
# required or already approved.  If approval is still Pending this is a no-op
# (the pack task will be created by the discount writeback script on approval).
# ---------------------------------------------------------------------------
$Script_SOAfterSubmitPack = @'
def _run():
    INVENTORY_ROLE = "Ops - Inventory"

    def assign_single_owner(task_name, user):
        frappe.db.set_value("Task", task_name, "_assign", frappe.as_json([user]), update_modified=False)
        other_todos = frappe.get_all(
            "ToDo",
            filters={
                "reference_type": "Task",
                "reference_name": task_name,
                "allocated_to": ["!=", user],
                "status": "Open",
            },
            pluck="name",
        )
        for td in (other_todos or []):
            frappe.db.set_value("ToDo", td, "status", "Cancelled")
        if not frappe.db.exists(
            "ToDo",
            {"reference_type": "Task", "reference_name": task_name, "allocated_to": user, "status": "Open"},
        ):
            todo = frappe.new_doc("ToDo")
            todo.status = "Open"
            todo.allocated_to = user
            todo.reference_type = "Task"
            todo.reference_name = task_name
            todo.description = frappe.db.get_value("Task", task_name, "subject") or task_name
            todo.assigned_by = frappe.session.user
            todo.insert(ignore_permissions=True)

    approval_status = doc.discount_approval_status or "Not Required"
    if approval_status not in ("Not Required", "Approved"):
        return

    existing = frappe.get_all(
        "Task",
        filters={
            "task_kind": "Pack / prepare items",
            "sales_order": doc.name,
            "status": ["!=", "Cancelled"],
        },
        pluck="name",
    )
    if existing:
        return

    task = frappe.new_doc("Task")
    task.subject = "Pack - " + doc.name
    task.status = "Open"
    task.task_kind = "Pack / prepare items"
    task.task_access_policy = "Pack / prepare items"
    task.sales_order = doc.name
    task.customer = doc.customer or ""
    task.insert(ignore_permissions=True)

    inventory_users = frappe.get_all("Has Role", filters={"role": INVENTORY_ROLE}, pluck="parent")
    inventory_users = sorted(list(set(inventory_users or [])))
    inventory_users = [
        u for u in inventory_users
        if u not in ("Administrator", "Guest") and int(frappe.db.get_value("User", u, "enabled") or 0) == 1
    ]
    if inventory_users:
        assign_single_owner(task.name, inventory_users[0])

_run()
'@

# ---------------------------------------------------------------------------
# Gap 1b — UPDATE existing: Task-before-save-discount-approval-writeback
# Fires: Task > Before Save
# Extended from original: after writing approval outcome back to the SO,
# also creates the Pack task when outcome = Approved and the SO is submitted.
# ---------------------------------------------------------------------------
$Script_DiscountWriteback = @'
def _run():
    before = doc.get_doc_before_save()
    before_status = before.status if before else None

    is_becoming_completed = (doc.status == "Completed" and before_status != "Completed")

    if not is_becoming_completed:
        return

    if doc.task_kind != "Discount Approval":
        return

    if not doc.sales_order:
        frappe.throw("Discount Approval task must be linked to a Sales Order.")

    if doc.approval_outcome not in ("Approved", "Rejected"):
        frappe.throw("Approval Outcome must be set to Approved or Rejected before completing the task.")

    frappe.db.set_value(
        "Sales Order",
        doc.sales_order,
        {
            "discount_approval_status": doc.approval_outcome,
            "discount_approval_note": doc.approval_note or "",
            "discount_approval_task": doc.name,
        },
    )

    if doc.approval_outcome != "Approved":
        return

    so_docstatus = frappe.db.get_value("Sales Order", doc.sales_order, "docstatus")
    if int(so_docstatus or 0) != 1:
        return

    existing_pack = frappe.get_all(
        "Task",
        filters={
            "task_kind": "Pack / prepare items",
            "sales_order": doc.sales_order,
            "status": ["!=", "Cancelled"],
        },
        pluck="name",
    )
    if existing_pack:
        return

    INVENTORY_ROLE = "Ops - Inventory"

    def assign_single_owner(task_name, user):
        frappe.db.set_value("Task", task_name, "_assign", frappe.as_json([user]), update_modified=False)
        other_todos = frappe.get_all(
            "ToDo",
            filters={
                "reference_type": "Task",
                "reference_name": task_name,
                "allocated_to": ["!=", user],
                "status": "Open",
            },
            pluck="name",
        )
        for td in (other_todos or []):
            frappe.db.set_value("ToDo", td, "status", "Cancelled")
        if not frappe.db.exists(
            "ToDo",
            {"reference_type": "Task", "reference_name": task_name, "allocated_to": user, "status": "Open"},
        ):
            todo = frappe.new_doc("ToDo")
            todo.status = "Open"
            todo.allocated_to = user
            todo.reference_type = "Task"
            todo.reference_name = task_name
            todo.description = frappe.db.get_value("Task", task_name, "subject") or task_name
            todo.assigned_by = frappe.session.user
            todo.insert(ignore_permissions=True)

    so_customer = frappe.db.get_value("Sales Order", doc.sales_order, "customer")
    pack_task = frappe.new_doc("Task")
    pack_task.subject = "Pack - " + doc.sales_order
    pack_task.status = "Open"
    pack_task.task_kind = "Pack / prepare items"
    pack_task.task_access_policy = "Pack / prepare items"
    pack_task.sales_order = doc.sales_order
    pack_task.customer = so_customer or ""
    pack_task.insert(ignore_permissions=True)

    inventory_users = frappe.get_all("Has Role", filters={"role": INVENTORY_ROLE}, pluck="parent")
    inventory_users = sorted(list(set(inventory_users or [])))
    inventory_users = [
        u for u in inventory_users
        if u not in ("Administrator", "Guest") and int(frappe.db.get_value("User", u, "enabled") or 0) == 1
    ]
    if inventory_users:
        assign_single_owner(pack_task.name, inventory_users[0])

_run()
'@

# ---------------------------------------------------------------------------
# Gap 2 — NEW script: Task-before-save-pack-complete-creates-delivery-task
# Fires: Task > Before Save
# When a "Pack / prepare items" task transitions to Completed, auto-creates
# a "Delivery" task assigned to the first active Delivery Driver (or Ops -
# Delivery as fallback).  Idempotent: skipped if a non-cancelled Delivery
# task already exists for the same Sales Order.
# ---------------------------------------------------------------------------
$Script_PackCompleteDelivery = @'
def _run():
    before = doc.get_doc_before_save()
    before_status = before.status if before else None

    is_becoming_completed = (doc.status == "Completed" and before_status != "Completed")

    if not is_becoming_completed:
        return

    if doc.task_kind != "Pack / prepare items":
        return

    if not doc.sales_order:
        return

    DELIVERY_ROLES = ["Delivery Driver", "Ops - Delivery"]

    def assign_single_owner(task_name, user):
        frappe.db.set_value("Task", task_name, "_assign", frappe.as_json([user]), update_modified=False)
        other_todos = frappe.get_all(
            "ToDo",
            filters={
                "reference_type": "Task",
                "reference_name": task_name,
                "allocated_to": ["!=", user],
                "status": "Open",
            },
            pluck="name",
        )
        for td in (other_todos or []):
            frappe.db.set_value("ToDo", td, "status", "Cancelled")
        if not frappe.db.exists(
            "ToDo",
            {"reference_type": "Task", "reference_name": task_name, "allocated_to": user, "status": "Open"},
        ):
            todo = frappe.new_doc("ToDo")
            todo.status = "Open"
            todo.allocated_to = user
            todo.reference_type = "Task"
            todo.reference_name = task_name
            todo.description = frappe.db.get_value("Task", task_name, "subject") or task_name
            todo.assigned_by = frappe.session.user
            todo.insert(ignore_permissions=True)

    existing = frappe.get_all(
        "Task",
        filters={
            "task_kind": "Delivery",
            "sales_order": doc.sales_order,
            "status": ["!=", "Cancelled"],
        },
        pluck="name",
    )
    if existing:
        return

    so_customer = frappe.db.get_value("Sales Order", doc.sales_order, "customer")

    delivery_task = frappe.new_doc("Task")
    delivery_task.subject = "Deliver - " + doc.sales_order
    delivery_task.status = "Open"
    delivery_task.task_kind = "Delivery"
    delivery_task.task_access_policy = "Delivery"
    delivery_task.sales_order = doc.sales_order
    delivery_task.customer = so_customer or ""
    delivery_task.insert(ignore_permissions=True)

    for role in DELIVERY_ROLES:
        users = frappe.get_all("Has Role", filters={"role": role}, pluck="parent")
        users = sorted(list(set(users or [])))
        users = [
            u for u in users
            if u not in ("Administrator", "Guest") and int(frappe.db.get_value("User", u, "enabled") or 0) == 1
        ]
        if users:
            assign_single_owner(delivery_task.name, users[0])
            break

_run()
'@

# ---------------------------------------------------------------------------
# Script definitions
# ---------------------------------------------------------------------------
$ScriptDefs = @(
    [pscustomobject]@{
        name              = "Sales Order-after-submit-pack-task"
        script_type       = "DocType Event"
        reference_doctype = "Sales Order"
        doctype_event     = "After Submit"
        event_frequency   = "All"
        allow_guest       = 0
        disabled          = 0
        enable_rate_limit = 0
        script            = $Script_SOAfterSubmitPack
    },
    [pscustomobject]@{
        name              = "Task-before-save-discount-approval-writeback"
        script_type       = "DocType Event"
        reference_doctype = "Task"
        doctype_event     = "Before Save"
        event_frequency   = "All"
        allow_guest       = 0
        disabled          = 0
        enable_rate_limit = 0
        script            = $Script_DiscountWriteback
    },
    [pscustomobject]@{
        name              = "Task-before-save-pack-complete-creates-delivery-task"
        script_type       = "DocType Event"
        reference_doctype = "Task"
        doctype_event     = "Before Save"
        event_frequency   = "All"
        allow_guest       = 0
        disabled          = 0
        enable_rate_limit = 0
        script            = $Script_PackCompleteDelivery
    }
)

# ---------------------------------------------------------------------------
# CHECK MODE
# ---------------------------------------------------------------------------
if ($Mode -eq "Check") {
    $Report = @()
    foreach ($S in $ScriptDefs) {
        $E = Get-ErpDoc -DocType "Server Script" -Name $S.name
        $Report += [pscustomobject]@{
            name     = $S.name
            exists   = ($null -ne $E)
            disabled = if ($null -ne $E) { $E.disabled } else { $null }
        }
    }
    $Report | ConvertTo-Json -Depth 5
    return
}

# ---------------------------------------------------------------------------
# DEPLOY MODE
# ---------------------------------------------------------------------------
$Results = @()
foreach ($S in $ScriptDefs) {
    $Body = [ordered]@{
        script_type       = $S.script_type
        reference_doctype = $S.reference_doctype
        doctype_event     = $S.doctype_event
        event_frequency   = $S.event_frequency
        allow_guest       = $S.allow_guest
        disabled          = $S.disabled
        enable_rate_limit = $S.enable_rate_limit
        script            = $S.script
    }
    $Result = Upsert-ErpDoc -DocType "Server Script" -Name $S.name -Body $Body
    $Results += $Result
    Write-Host "$($Result.action): $($Result.name)"
}

Write-Host ""
Write-Host "--- Post-deploy verification ---"
foreach ($S in $ScriptDefs) {
    $E = Get-ErpDoc -DocType "Server Script" -Name $S.name
    Write-Host "$($S.name): exists=$($null -ne $E) disabled=$(if ($null -ne $E) { $E.disabled } else { 'n/a' })"
}

$Results | ConvertTo-Json -Depth 5
