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

function Enc ([string]$s) { [uri]::EscapeDataString($s) }
function Invoke-ErpRequest { param([string]$Method, [string]$Path, $Body=$null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 120 }
    $Json = $Body | ConvertTo-Json -Depth 40
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 120
}
function Get-ErpDoc { param([string]$DocType,[string]$Name)
    try { return (Invoke-ErpRequest -Method Get -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)").data } catch { return $null }
}
function Upsert-ErpDoc { param([string]$DocType,[string]$Name,$Body)
    $Existing = Get-ErpDoc $DocType $Name
    if ($null -eq $Existing) { $Body.name=$Name; $C=(Invoke-ErpRequest Post "/api/resource/$(Enc $DocType)" $Body).data; return [pscustomobject]@{action="created";name=$C.name} }
    $U=(Invoke-ErpRequest Put "/api/resource/$(Enc $DocType)/$(Enc $Name)" $Body).data; return [pscustomobject]@{action="updated";name=$U.name}
}

# Server Script API to mark item as packed via checkbox
$MarkItemPackedApi = @'
case_name = frappe.form_dict.get("case_name")
item_idx = frappe.form_dict.get("item_idx")
packed = frappe.form_dict.get("packed")

if not case_name:
    frappe.throw("Dispatch Case is required.")
if item_idx is None:
    frappe.throw("Item index is required.")

case = frappe.get_doc("Dispatch Case", case_name)
idx = int(item_idx)

if idx < 0 or idx >= len(case.case_items):
    frappe.throw("Invalid item index.")

row = case.case_items[idx]
required_qty = float(row.dispatched_qty or 0)

if packed:
    # Mark as fully packed
    row.custom_scanned_qty = required_qty
    row.custom_remaining_qty = 0
    row.custom_packing_status = "Packed"
else:
    # Mark as not packed
    row.custom_scanned_qty = 0
    row.custom_remaining_qty = required_qty
    row.custom_packing_status = "Not Started"

case.flags.ignore_permissions = True
case.save()

frappe.response["message"] = {
    "ok": True,
    "item_code": row.item_code,
    "packed": packed,
    "scanned_qty": row.custom_scanned_qty,
    "remaining_qty": row.custom_remaining_qty
}
'@

# Updated client script with checkboxes
$ClientScriptWithCheckboxes = @'
function task_product_work_area_refresh(frm, show_alert) {
    const is_product_task = task_product_work_area_is_product_task(frm);
    if (!is_product_task) {
        if (frm.fields_dict.custom_task_product_summary) {
            frm.fields_dict.custom_task_product_summary.$wrapper.empty();
        }
        return;
    }
    if (!frm.doc.dispatch_case) {
        task_product_work_area_empty(frm, "No Dispatch Case / Packing Items linked yet. Use Create Dispatch Case / Items, then add product rows.", "warning");
        frm.set_value("custom_task_product_warning", "No Dispatch Case / Packing Items linked yet.");
        return;
    }
    frappe.call({
        method: "frappe.client.get",
        args: { doctype: "Dispatch Case", name: frm.doc.dispatch_case },
        callback: function(r) {
            const doc = r.message;
            if (!doc) {
                task_product_work_area_empty(frm, "Linked Dispatch Case was not found.", "danger");
                frm.set_value("custom_task_product_warning", "Linked Dispatch Case was not found.");
                return;
            }
            const rows = doc.case_items || [];
            if (!rows.length) {
                task_product_work_area_empty(frm, "No product rows yet. Add products in the linked Dispatch Case / Packing Items.", "warning");
                frm.set_value("custom_task_product_warning", "No product rows yet in Dispatch Case / Packing Items.");
                return;
            }
            // Determine labels based on task kind
            const is_returns_task = (frm.doc.task_kind === "Returns processing / verification");
            const checkbox_label = is_returns_task ? "Returned?" : "Packed?";
            const col1_label = is_returns_task ? "Dispatched" : "Required";
            const col2_label = is_returns_task ? "Returned" : "Scanned";
            const col3_label = is_returns_task ? "Used" : "Missing";
            
            let html = `<div class="small text-muted" style="margin-bottom:8px">Source: <b>${frappe.utils.escape_html(doc.name)}</b> · Customer: <b>${frappe.utils.escape_html(doc.customer || "")}</b></div>`;
            html += `<div style="overflow-x:auto"><table class="table table-bordered table-condensed"><thead><tr>
                <th style="width:60px">${checkbox_label}</th><th>Name</th><th>${col1_label}</th><th>${col2_label}</th><th>${col3_label}</th><th>Batch/LOT</th><th>Expiry</th><th>Status</th><th>Warning / Problem</th>
            </tr></thead><tbody>`;
            rows.forEach(function(row, idx) {
                const required = flt(row.dispatched_qty || 0);
                const scanned = flt(row.custom_scanned_qty || 0);
                const remaining = row.custom_remaining_qty !== undefined && row.custom_remaining_qty !== null ? flt(row.custom_remaining_qty) : Math.max(required - scanned, 0);
                const warn = row.custom_fefo_warning || row.custom_problem_reason || "";
                const status = row.custom_packing_status || (remaining <= 0 ? "Packed" : scanned > 0 ? "Partial" : "Not Started");
                const is_packed = (status === "Packed" || remaining <= 0);
                const checkbox_id = `pack_checkbox_${idx}`;
                html += `<tr>
                    <td class="text-center">
                        <input type="checkbox" id="${checkbox_id}" data-idx="${idx}" ${is_packed ? 'checked' : ''} 
                               onchange="task_product_work_area_toggle_packed(this, '${frappe.utils.escape_html(frm.doc.dispatch_case)}', ${idx})">
                    </td>
                    <td>${frappe.utils.escape_html(row.item_name || "")}</td>
                    <td class="text-right">${required}</td>
                    <td class="text-right">${scanned}</td>
                    <td class="text-right">${remaining}</td>
                    <td>${frappe.utils.escape_html(row.batch_no || "")}</td>
                    <td>${frappe.utils.escape_html(row.expiry_date || row.custom_expiry_date || "")}</td>
                    <td><span class="indicator ${is_packed ? 'green' : 'orange'}">${frappe.utils.escape_html(status)}</span></td>
                    <td>${frappe.utils.escape_html(warn)}</td>
                </tr>`;
            });
            html += `</tbody></table></div>`;
            const tip_text = is_returns_task 
                ? `Tip: Check the box when the item was returned by the customer. The "${col2_label}" column will update to match "${col1_label}" and "${col3_label}" will become 0.`
                : `Tip: Check the box when you've packed the item. The "${col2_label}" column will update to match "${col1_label}" and "${col3_label}" will become 0.`;
            html += `<div class="small text-muted" style="margin-top:8px"><i>${tip_text}</i></div>`;
            if (frm.fields_dict.custom_task_product_summary) {
                frm.fields_dict.custom_task_product_summary.$wrapper.html(html);
            }
            frm.set_value("custom_task_product_warning", doc.custom_packing_last_warning || doc.custom_packing_problem_summary || "");
            if (show_alert) {
                frappe.show_alert({ message: __("Product summary refreshed"), indicator: "green" });
            }
        }
    });
}

function task_product_work_area_toggle_packed(checkbox, case_name, idx) {
    const packed = checkbox.checked;
    frappe.call({
        method: "task_mark_item_packed",
        args: {
            case_name: case_name,
            item_idx: idx,
            packed: packed ? 1 : 0
        },
        freeze: true,
        freeze_message: packed ? __("Marking as packed...") : __("Marking as not packed..."),
        callback: function(r) {
            const msg = r.message || {};
            if (msg.ok) {
                frappe.show_alert({ 
                    message: packed ? __("Marked as packed: {0}", [msg.item_code]) : __("Marked as not packed: {0}", [msg.item_code]), 
                    indicator: "green" 
                });
                // Mark form as dirty so Save works
                const frm = cur_frm;
                if (frm) {
                    frm.doc.__unsaved = 1;
                    frm.page.set_indicator(__("Not Saved"), "orange");
                    task_product_work_area_refresh(frm, false);
                }
            }
        },
        error: function() {
            // Revert checkbox on error
            checkbox.checked = !packed;
            frappe.show_alert({ message: __("Failed to update packing status"), indicator: "red" });
        }
    });
}

function task_product_work_area_is_product_task(frm) {
    const kinds = [
        "Pack / prepare items", "Dispatch picking / hand-off", "Delivery", "Pickup Returns",
        "Return drop-off at warehouse", "Returns processing / verification", "Returns restocking",
        "Invoice preparation / create invoice", "Discount Approval"
    ];
    return !!frm.doc.dispatch_case || kinds.includes(frm.doc.task_kind);
}

function task_product_work_area_empty(frm, message, indicator) {
    if (frm.fields_dict.custom_task_product_summary) {
        frm.fields_dict.custom_task_product_summary.$wrapper.html(
            `<div class="alert alert-${indicator || "warning"}">${frappe.utils.escape_html(message)}</div>`
        );
    }
}

frappe.ui.form.on("Task", {
    refresh(frm) {
        task_product_work_area_refresh(frm);
        const is_product_task = task_product_work_area_is_product_task(frm);
        if (!frm.is_new() && is_product_task) {
            frm.add_custom_button(__("Refresh Packing Status"), function() {
                task_product_work_area_refresh(frm, true);
            }, __("Packing"));
        }
    },
    dispatch_case(frm) {
        task_product_work_area_refresh(frm, true);
    },
    task_kind(frm) {
        task_product_work_area_refresh(frm, true);
    }
});
'@

$Report = [ordered]@{
    mode = $Mode
    server_scripts = @()
    client_scripts = @()
    notes = @()
}

$ServerName = "task_mark_item_packed"
$E = Get-ErpDoc "Server Script" $ServerName
if ($Mode -eq "Deploy") {
    $Report.server_scripts += Upsert-ErpDoc "Server Script" $ServerName ([ordered]@{
        script_type = "API"
        api_method = "task_mark_item_packed"
        allow_guest = 0
        disabled = 0
        enable_rate_limit = 0
        script = $MarkItemPackedApi
    })
} else {
    $Report.server_scripts += [pscustomobject]@{ name = $ServerName; exists = ($null -ne $E) }
}

$ClientName = "Task-Packing Checkboxes"
$E = Get-ErpDoc "Client Script" $ClientName
if ($Mode -eq "Deploy") {
    $Report.client_scripts += Upsert-ErpDoc "Client Script" $ClientName ([ordered]@{
        dt = "Task"
        view = "Form"
        enabled = 1
        script = $ClientScriptWithCheckboxes
    })
} else {
    $Report.client_scripts += [pscustomobject]@{ name = $ClientName; exists = ($null -ne $E) }
}

$Report.notes += "Adds simple checkboxes to mark items as packed without barcode scanning."
$Report.notes += "For launch: workers click checkboxes to mark items as packed."
$Report.notes += "Post-launch: barcode scanning can be added later without touching this checkbox workflow."

$Report | ConvertTo-Json -Depth 40
