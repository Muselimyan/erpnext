param(
    [ValidateSet("Check", "Deploy", "Verify")]
    [string]$Mode = "Check"
)

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{
    Authorization = "token $($ApiKey):$($ApiSec)"
    "Content-Type" = "application/json"
}

function Enc([string]$Value) {
    return [uri]::EscapeDataString($Value)
}

function Invoke-ErpRequest {
    param(
        [string]$Method,
        [string]$Path,
        $Body = $null
    )

    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) {
        return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method
    }

    $Json = $Body | ConvertTo-Json -Depth 30
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body $Json
}

function Get-ErpDoc {
    param([string]$DocType, [string]$Name)

    try {
        return (Invoke-ErpRequest -Method Get -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)").data
    }
    catch {
        return $null
    }
}

function Get-ErpList {
    param(
        [string]$DocType,
        [array]$Fields = @("name"),
        [array]$Filters = @(),
        [int]$Limit = 20
    )

    $FieldsJson = $Fields | ConvertTo-Json -Compress
    $Path = "/api/resource/$(Enc $DocType)?limit_page_length=$Limit&fields=$(Enc $FieldsJson)"
    if ($Filters.Count -gt 0) {
        $FiltersJson = $Filters | ConvertTo-Json -Compress -Depth 10
        $Path += "&filters=$(Enc $FiltersJson)"
    }
    return (Invoke-ErpRequest -Method Get -Path $Path).data
}

function Upsert-ErpDoc {
    param([string]$DocType, [string]$Name, $Body)

    $Existing = Get-ErpDoc -DocType $DocType -Name $Name
    if ($null -eq $Existing) {
        $Body.name = $Name
        $Created = (Invoke-ErpRequest -Method Post -Path "/api/resource/$(Enc $DocType)" -Body $Body).data
        return [pscustomobject]@{ doctype = $DocType; name = $Name; action = "created"; result = $Created.name }
    }

    $Updated = (Invoke-ErpRequest -Method Put -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)" -Body $Body).data
    return [pscustomobject]@{ doctype = $DocType; name = $Name; action = "updated"; result = $Updated.name }
}

$CustomFields = @(
    [pscustomobject]@{ name = "Task-purchase_order"; body = [ordered]@{ doctype = "Custom Field"; dt = "Task"; label = "Purchase Order"; fieldname = "purchase_order"; fieldtype = "Link"; options = "Purchase Order"; insert_after = "task_kind"; reqd = 0; read_only = 0 } },
    [pscustomobject]@{ name = "Task-approval_outcome"; body = [ordered]@{ doctype = "Custom Field"; dt = "Task"; label = "Approval Outcome"; fieldname = "approval_outcome"; fieldtype = "Select"; options = "Approved`nRejected"; insert_after = "purchase_order"; reqd = 0; read_only = 0 } },
    [pscustomobject]@{ name = "Task-approval_note"; body = [ordered]@{ doctype = "Custom Field"; dt = "Task"; label = "Approval Note"; fieldname = "approval_note"; fieldtype = "Small Text"; insert_after = "approval_outcome"; reqd = 0; read_only = 0 } },
    [pscustomobject]@{ name = "Purchase Order-purchase_reason"; body = [ordered]@{ doctype = "Custom Field"; dt = "Purchase Order"; label = "Purchase Reason"; fieldname = "purchase_reason"; fieldtype = "Select"; options = "Reorder (Doc 08)`nAd-hoc demand`nReplacement (damaged/expired/write-off)`nEmergency"; insert_after = "schedule_date"; reqd = 1; read_only = 0 } },
    [pscustomobject]@{ name = "Purchase Order-requested_by"; body = [ordered]@{ doctype = "Custom Field"; dt = "Purchase Order"; label = "Requested By"; fieldname = "requested_by"; fieldtype = "Link"; options = "User"; insert_after = "purchase_reason"; reqd = 1; read_only = 0 } },
    [pscustomobject]@{ name = "Purchase Order-director_approval_status"; body = [ordered]@{ doctype = "Custom Field"; dt = "Purchase Order"; label = "Director Approval Status"; fieldname = "director_approval_status"; fieldtype = "Select"; options = "Pending`nApproved`nRejected"; default = "Pending"; insert_after = "requested_by"; reqd = 0; read_only = 1 } },
    [pscustomobject]@{ name = "Purchase Order-director_approved_by"; body = [ordered]@{ doctype = "Custom Field"; dt = "Purchase Order"; label = "Director Approved By"; fieldname = "director_approved_by"; fieldtype = "Link"; options = "User"; insert_after = "director_approval_status"; reqd = 0; read_only = 1 } },
    [pscustomobject]@{ name = "Purchase Order-director_approved_at"; body = [ordered]@{ doctype = "Custom Field"; dt = "Purchase Order"; label = "Director Approved At"; fieldname = "director_approved_at"; fieldtype = "Datetime"; insert_after = "director_approved_by"; reqd = 0; read_only = 1 } },
    [pscustomobject]@{ name = "Purchase Order-director_approval_task"; body = [ordered]@{ doctype = "Custom Field"; dt = "Purchase Order"; label = "Director Approval Task"; fieldname = "director_approval_task"; fieldtype = "Link"; options = "Task"; insert_after = "director_approved_at"; reqd = 0; read_only = 1 } },
    [pscustomobject]@{ name = "Purchase Order-director_approval_note"; body = [ordered]@{ doctype = "Custom Field"; dt = "Purchase Order"; label = "Director Approval Note"; fieldname = "director_approval_note"; fieldtype = "Small Text"; insert_after = "director_approval_task"; reqd = 0; read_only = 1 } }
)

$TaskApprovalWriteback = @'
before = doc.get_doc_before_save()
before_status = before.status if before else None

is_becoming_completed = (doc.status == "Completed" and before_status != "Completed")

if is_becoming_completed and doc.task_kind == "Purchase Approval":
    if not doc.purchase_order:
        frappe.throw("Purchase Approval task must be linked to a Purchase Order.")

    if doc.approval_outcome not in ("Approved", "Rejected"):
        frappe.throw("Approval Outcome must be set to Approved or Rejected before completing the task.")

    po = frappe.get_doc("Purchase Order", doc.purchase_order)

    po.director_approval_status = doc.approval_outcome
    po.director_approved_by = doc.modified_by or doc.owner
    po.director_approved_at = now_datetime()
    po.director_approval_task = doc.name
    po.director_approval_note = doc.approval_note

    po.save(ignore_permissions=True)
'@

$PoBeforeSubmit = @'
if doc.director_approval_status != "Approved":
    frappe.throw(
        "Director approval is required before submitting the Purchase Order. "
        "Create a Purchase Approval task, get it completed as Approved, then submit."
    )
'@

$PoValidateSupplier = @'
if doc.supplier:
    for row in (doc.items or []):
        if not row.item_code:
            continue

        suppliers = frappe.get_all(
            "Item Supplier",
            filters={"parent": row.item_code, "parenttype": "Item"},
            pluck="supplier",
        )

        suppliers = [s for s in (suppliers or []) if s]

        if len(suppliers) != 1:
            frappe.throw(
                f"Item {row.item_code} must have exactly 1 Supplier (Doc 07 policy). Found: {', '.join(suppliers) or 'none'}."
            )

        if suppliers[0] != doc.supplier:
            frappe.throw(
                f"Item {row.item_code} supplier is {suppliers[0]} but PO supplier is {doc.supplier}. Do not mix suppliers on one PO."
            )
'@

$PoClearApproval = @'
before = doc.get_doc_before_save()

if before and doc.docstatus == 0:
    was_approved = (before.director_approval_status == "Approved")

    if was_approved:
        header_changed = (
            (doc.supplier != before.supplier)
            or (doc.currency != before.currency)
            or (doc.transaction_date != before.transaction_date)
            or (doc.purchase_reason != before.purchase_reason)
            or (doc.requested_by != before.requested_by)
        )

        def normalize_rows(rows):
            out = []
            for r in (rows or []):
                out.append({
                    "item_code": r.item_code,
                    "uom": r.uom,
                    "conversion_factor": r.conversion_factor,
                    "qty": float(r.qty or 0),
                    "rate": float(r.rate or 0),
                    "schedule_date": str(r.schedule_date or ""),
                })
            return out

        rows_changed = (normalize_rows(doc.items) != normalize_rows(before.items))

        if header_changed or rows_changed:
            doc.director_approval_status = "Pending"
            doc.director_approved_by = None
            doc.director_approved_at = None
            doc.director_approval_task = None
            doc.director_approval_note = None

            frappe.msgprint("PO was edited after director approval. Approval was cleared and must be re-done.")
'@

$PrBeforeSubmit = @'
MAIN_WH = "Main - Inmed"

for row in (doc.items or []):
    if row.warehouse != MAIN_WH:
        frappe.throw(f"Receiving must be into {MAIN_WH}. Row warehouse is {row.warehouse or 'not set'}.")

    if not row.item_code:
        continue

    item = frappe.get_doc("Item", row.item_code)

    requires_expiry = bool(item.get("has_expiry_date"))
    has_batch = bool(item.get("has_batch_no"))

    if requires_expiry and has_batch:
        if not row.batch_no:
            frappe.throw(f"Row for item {row.item_code} requires Batch + Expiry. Batch No is missing.")

        batch = frappe.get_doc("Batch", row.batch_no)
        if not batch.expiry_date:
            frappe.throw(f"Batch {row.batch_no} must have Expiry Date for item {row.item_code}.")
'@

$PiBeforeSubmit = @'
if doc.get("update_stock"):
    frappe.throw("Do not use Purchase Invoice to update stock. Use Purchase Receipt for receiving (Doc 07 policy).")
'@

$ServerScripts = @(
    [pscustomobject]@{ name = "Task-purchase-approval-writeback"; reference_doctype = "Task"; doctype_event = "Before Save"; script = $TaskApprovalWriteback },
    [pscustomobject]@{ name = "Purchase Order-before-submit-director-approval"; reference_doctype = "Purchase Order"; doctype_event = "Before Submit"; script = $PoBeforeSubmit },
    [pscustomobject]@{ name = "Purchase Order-validate-one-supplier"; reference_doctype = "Purchase Order"; doctype_event = "Before Save"; script = $PoValidateSupplier },
    [pscustomobject]@{ name = "Purchase Order-before-save-clear-approval"; reference_doctype = "Purchase Order"; doctype_event = "Before Save"; script = $PoClearApproval },
    [pscustomobject]@{ name = "Purchase Receipt-before-submit-main-inmed-expiry"; reference_doctype = "Purchase Receipt"; doctype_event = "Before Submit"; script = $PrBeforeSubmit },
    [pscustomobject]@{ name = "Purchase Invoice-before-submit-no-update-stock"; reference_doctype = "Purchase Invoice"; doctype_event = "Before Submit"; script = $PiBeforeSubmit }
)

function Get-StatusSnapshot {
    $FieldStatus = foreach ($Field in $CustomFields) {
        $Doc = Get-ErpDoc -DocType "Custom Field" -Name $Field.name
        [pscustomobject]@{ name = $Field.name; exists = ($null -ne $Doc); dt = $Doc.dt; fieldtype = $Doc.fieldtype; reqd = $Doc.reqd; read_only = $Doc.read_only }
    }

    $ScriptStatus = foreach ($Script in $ServerScripts) {
        $Doc = Get-ErpDoc -DocType "Server Script" -Name $Script.name
        [pscustomobject]@{ name = $Script.name; exists = ($null -ne $Doc); script_type = $Doc.script_type; reference_doctype = $Doc.reference_doctype; doctype_event = $Doc.doctype_event; disabled = $Doc.disabled }
    }

    [ordered]@{
        mode = $Mode
        logged_user = (Invoke-ErpRequest -Method Get -Path "/api/method/frappe.auth.get_logged_user").message
        main_warehouses = Get-ErpList -DocType "Warehouse" -Fields @("name", "warehouse_name", "company", "is_group") -Filters @(@("Warehouse", "warehouse_name", "=", "Main")) -Limit 20
        purchase_documents_sample = [ordered]@{
            purchase_orders = Get-ErpList -DocType "Purchase Order" -Fields @("name", "docstatus", "status", "modified") -Limit 10
            purchase_receipts = Get-ErpList -DocType "Purchase Receipt" -Fields @("name", "docstatus", "status", "modified") -Limit 10
            purchase_invoices = Get-ErpList -DocType "Purchase Invoice" -Fields @("name", "docstatus", "status", "modified") -Limit 10
        }
        target_custom_fields = $FieldStatus
        target_server_scripts = $ScriptStatus
    }
}

if ($Mode -eq "Check") {
    Get-StatusSnapshot | ConvertTo-Json -Depth 12
    exit 0
}

$Results = @()
foreach ($Field in $CustomFields) {
    $Results += Upsert-ErpDoc -DocType "Custom Field" -Name $Field.name -Body $Field.body
}

foreach ($Script in $ServerScripts) {
    $Body = [ordered]@{
        doctype = "Server Script"
        script_type = "DocType Event"
        event_frequency = "All"
        reference_doctype = $Script.reference_doctype
        doctype_event = $Script.doctype_event
        allow_guest = 0
        disabled = 0
        enable_rate_limit = 0
        script = $Script.script
    }
    $Results += Upsert-ErpDoc -DocType "Server Script" -Name $Script.name -Body $Body
}

[ordered]@{
    mode = $Mode
    results = $Results
    verification = Get-StatusSnapshot
} | ConvertTo-Json -Depth 12
