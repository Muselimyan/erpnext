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
$Headers    = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json"; "User-Agent" = "Mozilla/5.0" }

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
function Build-CustomFieldBody { param($f)
    $Body=[ordered]@{dt=$f.dt;fieldname=$f.fieldname;label=$f.label;fieldtype=$f.fieldtype;insert_after=$f.insert_after;hidden=0;depends_on=$f.depends_on}
    if($f.options){$Body.options=$f.options}
    if($null -ne $f.default){$Body.default=$f.default}
    if($null -ne $f.read_only){$Body.read_only=$f.read_only}
    return $Body
}

$DispatchDepends = ''
$PackDepends = ''

$Fields = @(
    [pscustomobject]@{name="Task-custom_product_work_section";dt="Task";fieldname="custom_product_work_section";label="Products / Dispatch Work";fieldtype="Section Break";insert_after="dispatch_case";depends_on=$DispatchDepends},
    [pscustomobject]@{name="Task-custom_task_product_summary";dt="Task";fieldname="custom_task_product_summary";label="Product Summary";fieldtype="HTML";insert_after="custom_product_work_section";depends_on=$DispatchDepends;read_only=1},
    [pscustomobject]@{name="Task-custom_task_add_item_code";dt="Task";fieldname="custom_task_add_item_code";label="Choose Product";fieldtype="Link";options="Item";insert_after="custom_task_product_summary";depends_on=$DispatchDepends},
    [pscustomobject]@{name="Task-custom_task_add_qty";dt="Task";fieldname="custom_task_add_qty";label="Product Qty";fieldtype="Float";insert_after="custom_task_add_item_code";depends_on=$DispatchDepends;default="1"},
    [pscustomobject]@{name="Task-custom_task_add_batch_no";dt="Task";fieldname="custom_task_add_batch_no";label="Batch / LOT";fieldtype="Link";options="Batch";insert_after="custom_task_add_qty";depends_on=$DispatchDepends},
    [pscustomobject]@{name="Task-custom_task_add_unit_price";dt="Task";fieldname="custom_task_add_unit_price";label="Unit Price";fieldtype="Currency";insert_after="custom_task_add_batch_no";depends_on=$DispatchDepends;default="0"},
    [pscustomobject]@{name="Task-custom_task_scan_barcode";dt="Task";fieldname="custom_task_scan_barcode";label="Scan Product Barcode";fieldtype="Data";insert_after="custom_task_add_unit_price";depends_on=$PackDepends},
    [pscustomobject]@{name="Task-custom_task_scan_qty";dt="Task";fieldname="custom_task_scan_qty";label="Scan Qty";fieldtype="Float";insert_after="custom_task_scan_barcode";depends_on=$PackDepends;default="1"},
    [pscustomobject]@{name="Task-custom_task_scan_result";dt="Task";fieldname="custom_task_scan_result";label="Last Scan Result";fieldtype="Small Text";insert_after="custom_task_scan_qty";depends_on=$PackDepends;read_only=1},
    [pscustomobject]@{name="Task-custom_product_work_column";dt="Task";fieldname="custom_product_work_column";label="";fieldtype="Column Break";insert_after="custom_task_scan_result";depends_on=$DispatchDepends},
    [pscustomobject]@{name="Task-custom_task_product_warning";dt="Task";fieldname="custom_task_product_warning";label="Product Work Warning";fieldtype="Small Text";insert_after="custom_product_work_column";depends_on=$DispatchDepends;read_only=1}
)

$ClientScript = @'
function task_product_work_area_error_beep() {
    if (!(window.AudioContext || window.webkitAudioContext)) return;
    let audioContext = new (window.AudioContext || window.webkitAudioContext)();
    let oscillator = audioContext.createOscillator();
    let gainNode = audioContext.createGain();
    oscillator.connect(gainNode);
    gainNode.connect(audioContext.destination);
    oscillator.frequency.value = 400;
    oscillator.type = "sine";
    gainNode.gain.value = 0.3;
    oscillator.start(audioContext.currentTime);
    oscillator.stop(audioContext.currentTime + 0.2);
}

function task_product_work_area_focus_scan(frm) {
    setTimeout(() => {
        let field = frm.get_field("custom_task_scan_barcode");
        if (field && field.$input) {
            field.$input.val("").focus();
            setTimeout(() => field.$input.focus(), 100);
            return;
        }
        let scan = $('[data-fieldname="custom_task_scan_barcode"]:visible').find('input:visible').first();
        if (scan.length) {
            scan.val("").focus();
            setTimeout(() => scan.focus(), 100);
        }
    }, 200);
}

function task_product_work_area_parse_gs1(raw) {
    if (!raw || !raw.startsWith("]C111")) return null;
    let expiry_date = `20${raw.substring(13, 15)}-${raw.substring(15, 17)}-${raw.substring(17, 19)}`;
    let lot_ai_index = raw.indexOf("10", 19);
    if (lot_ai_index === -1) return null;
    let lot_number = raw.substring(lot_ai_index + 2);
    if (!lot_number) return null;
    return { expiry_date: expiry_date, lot_number: lot_number };
}

frappe.ui.form.on("Task", {
    refresh(frm) {
        task_product_work_area_refresh(frm);
        task_product_work_area_focus_scan(frm);
        const is_product_task = task_product_work_area_is_product_task(frm);
        if (!frm.is_new() && is_product_task) {
            frm.add_custom_button(__("Add Selected Product"), function() {
                task_product_work_area_add_product(frm);
            }, __("Products / Dispatch Work"));
            frm.add_custom_button(__("Refresh Products"), function() {
                task_product_work_area_refresh(frm, true);
            }, __("Products / Dispatch Work"));
        }
        if (!frm.is_new()) {
            frm.add_custom_button(__("Scan Product Barcode"), function() {
                task_product_work_area_scan(frm);
            }, __("Products / Dispatch Work"));
        }
    },
    dispatch_case(frm) {
        task_product_work_area_refresh(frm, true);
    },
    task_kind(frm) {
        task_product_work_area_refresh(frm, true);
    },
    custom_task_scan_barcode(frm) {
        if (frm.doc.custom_task_scan_barcode) {
            task_product_work_area_scan(frm);
        }
    },
    custom_task_add_item_code(frm) {
        if (frm.doc.custom_task_add_item_code) {
            frappe.db.get_value("Item", frm.doc.custom_task_add_item_code, ["item_name", "standard_rate"], function(v) {
                if (v && frm.doc.custom_task_add_unit_price === 0) {
                    frm.set_value("custom_task_add_unit_price", v.standard_rate || 0);
                }
            });
        }
    }
});

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

function task_product_work_area_refresh(frm, show_alert) {
    if (!task_product_work_area_is_product_task(frm)) {
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
            let html = `<div class="small text-muted" style="margin-bottom:8px">Source: <b>${frappe.utils.escape_html(doc.name)}</b> · Customer: <b>${frappe.utils.escape_html(doc.customer || "")}</b></div>`;
            html += `<div style="overflow-x:auto"><table class="table table-bordered table-condensed"><thead><tr>
                <th>Item</th><th>Name</th><th>Required</th><th>Scanned</th><th>Missing</th><th>Batch/LOT</th><th>Expiry</th><th>Status</th><th>Warning / Problem</th>
            </tr></thead><tbody>`;
            rows.forEach(function(row) {
                const required = flt(row.dispatched_qty || 0);
                const scanned = flt(row.custom_scanned_qty || 0);
                const remaining = row.custom_remaining_qty !== undefined && row.custom_remaining_qty !== null ? flt(row.custom_remaining_qty) : Math.max(required - scanned, 0);
                const warn = row.custom_fefo_warning || row.custom_problem_reason || "";
                const status = row.custom_packing_status || (remaining <= 0 ? "Packed" : scanned > 0 ? "Partial" : "Not Started");
                html += `<tr>
                    <td>${frappe.utils.escape_html(row.item_code || "")}</td>
                    <td>${frappe.utils.escape_html(row.item_name || "")}</td>
                    <td class="text-right">${required}</td>
                    <td class="text-right">${scanned}</td>
                    <td class="text-right">${remaining}</td>
                    <td>${frappe.utils.escape_html(row.batch_no || "")}</td>
                    <td>${frappe.utils.escape_html(row.expiry_date || row.custom_expiry_date || "")}</td>
                    <td>${frappe.utils.escape_html(status)}</td>
                    <td>${frappe.utils.escape_html(warn)}</td>
                </tr>`;
            });
            html += `</tbody></table></div>`;
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

function task_product_work_area_add_product(frm) {
    if (frm.is_new()) {
        frappe.msgprint(__("Save the Task before adding/scanning products."));
        task_product_work_area_error_beep();
        task_product_work_area_focus_scan(frm);
        return;
    }
    if (!frm.doc.dispatch_case) {
        frappe.msgprint(__("Create or link Dispatch Case / Packing Items first."));
        return;
    }
    if (!frm.doc.custom_task_add_item_code) {
        frappe.msgprint(__("Choose Product first."));
        return;
    }
    frappe.call({
        method: "task_add_dispatch_product",
        args: {
            task_name: frm.doc.name,
            item_code: frm.doc.custom_task_add_item_code,
            qty: frm.doc.custom_task_add_qty || 1,
            batch_no: frm.doc.custom_task_add_batch_no || "",
            unit_price: frm.doc.custom_task_add_unit_price || 0
        },
        freeze: true,
        freeze_message: __("Adding product..."),
        callback: function(r) {
            const msg = r.message || {};
            if (msg.ok) {
                frappe.show_alert({ message: __("Product added"), indicator: "green" });
                frm.set_value("custom_task_add_item_code", "");
                frm.set_value("custom_task_add_qty", 1);
                frm.set_value("custom_task_add_batch_no", "");
                frm.set_value("custom_task_add_unit_price", 0);
                task_product_work_area_refresh(frm, false);
            }
        }
    });
}

function task_product_work_area_scan(frm) {
    const barcode = (frm.doc.custom_task_scan_barcode || "").trim();
    if (!barcode) {
        frappe.msgprint(__("Scan or enter barcode first."));
        task_product_work_area_error_beep();
        task_product_work_area_focus_scan(frm);
        return;
    }

    if (barcode.startsWith("]C111")) {
        const parsed = task_product_work_area_parse_gs1(barcode);
        if (!parsed) {
            frm.set_value("custom_task_scan_result", __("Invalid GS1 LOT barcode."));
            frappe.show_alert({ message: __("Invalid GS1 LOT barcode."), indicator: "red" }, 5);
            task_product_work_area_error_beep();
            frm.set_value("custom_task_scan_barcode", "");
            task_product_work_area_focus_scan(frm);
            return;
        }
        if (!frm.doc.custom_task_add_item_code) {
            frm.set_value("custom_task_scan_result", __("Scan the REF/product barcode first, then scan the LOT/expiry barcode."));
            frappe.show_alert({ message: __("Scan REF/product barcode first."), indicator: "red" }, 5);
            task_product_work_area_error_beep();
            frm.set_value("custom_task_scan_barcode", "");
            task_product_work_area_focus_scan(frm);
            return;
        }
        frm.set_value("custom_task_add_batch_no", parsed.lot_number);
        frm.set_value("custom_task_scan_result", __("LOT/expiry captured: {0}, expiry {1}", [parsed.lot_number, parsed.expiry_date]));
        frm.set_value("custom_task_scan_barcode", "");
        task_product_work_area_add_product(frm);
        task_product_work_area_focus_scan(frm);
        return;
    }

    frappe.call({
        method: "task_lookup_product_barcode",
        args: { barcode: barcode },
        callback: function(r) {
            const item_code = r.message && r.message.item_code;
        if (item_code) {
            frm.set_value("custom_task_add_item_code", item_code);
            frm.set_value("custom_task_scan_result", __("Product selected from REF barcode: {0}. If this product has LOT/expiry, scan the second GS1 barcode now.", [item_code]));
            frappe.show_alert({ message: __("Product selected. Scan LOT/expiry barcode if needed."), indicator: "green" });
            frm.set_value("custom_task_scan_barcode", "");
            task_product_work_area_focus_scan(frm);
        } else {
            frm.set_value("custom_task_scan_result", __("Barcode did not identify an Item."));
            frappe.show_alert({ message: __("Barcode did not identify an Item."), indicator: "red" }, 5);
            task_product_work_area_error_beep();
            frm.set_value("custom_task_scan_barcode", "");
            task_product_work_area_focus_scan(frm);
        }
        },
        error: function() {
            task_product_work_area_error_beep();
            frm.set_value("custom_task_scan_barcode", "");
            task_product_work_area_focus_scan(frm);
        }
    });
}
'@

$LookupBarcodeApi = @'
def run_script():
    barcode = (frappe.form_dict.get("barcode") or "").strip()
    if not barcode:
        frappe.throw("Barcode is required.")
    item_code = None
    if frappe.db.exists("Item", barcode):
        item_code = barcode
    if not item_code:
        item_code = frappe.db.get_value("Item Barcode", {"barcode": barcode}, "parent")
    frappe.response["message"] = {"ok": True, "barcode": barcode, "item_code": item_code}
run_script()
'@

$AddProductApi = @'
def run_script():
    task_name = frappe.form_dict.get("task_name")
    item_code = frappe.form_dict.get("item_code")
    qty = float(frappe.form_dict.get("qty") or 1)
    batch_no = frappe.form_dict.get("batch_no")
    unit_price = float(frappe.form_dict.get("unit_price") or 0)
    if not task_name:
        frappe.throw("Task is required.")
    if not item_code:
        frappe.throw("Choose Product first.")
    task = frappe.get_doc("Task", task_name)
    if not task.get("dispatch_case"):
        frappe.throw("Create or link Dispatch Case / Packing Items first.")
    case = frappe.get_doc("Dispatch Case", task.dispatch_case)
    item_name = frappe.db.get_value("Item", item_code, "item_name") or item_code
    row = case.append("case_items", {})
    row.item_code = item_code
    row.item_name = item_name
    row.dispatched_qty = qty
    row.batch_no = batch_no or None
    row.unit_price = unit_price
    row.custom_scanned_qty = 0
    row.custom_remaining_qty = qty
    row.custom_packing_status = "Not Started"
    case.flags.ignore_permissions = True
    case.save()
    frappe.response["message"] = {"ok": True, "dispatch_case": case.name, "item_code": item_code}
run_script()
'@

$Report=[ordered]@{mode=$Mode;custom_fields=@();server_scripts=@();client_scripts=@();notes=@()}
foreach($f in $Fields){
    $E=Get-ErpDoc "Custom Field" $f.name
    if($Mode -eq "Deploy"){
        $Report.custom_fields += Upsert-ErpDoc "Custom Field" $f.name (Build-CustomFieldBody $f)
    } else { $Report.custom_fields += [pscustomobject]@{name=$f.name;exists=($null -ne $E)} }
}
$ClientName="Task-Product Work Area"
$LookupServerName="task_lookup_product_barcode"
$E=Get-ErpDoc "Server Script" $LookupServerName
if($Mode -eq "Deploy"){
    $Report.server_scripts += Upsert-ErpDoc "Server Script" $LookupServerName ([ordered]@{script_type="API";api_method="task_lookup_product_barcode";allow_guest=0;disabled=0;enable_rate_limit=0;script=$LookupBarcodeApi})
} else { $Report.server_scripts += [pscustomobject]@{name=$LookupServerName;exists=($null -ne $E)} }
$ServerName="task_add_dispatch_product"
$E=Get-ErpDoc "Server Script" $ServerName
if($Mode -eq "Deploy"){
    $Report.server_scripts += Upsert-ErpDoc "Server Script" $ServerName ([ordered]@{script_type="API";api_method="task_add_dispatch_product";allow_guest=0;disabled=0;enable_rate_limit=0;script=$AddProductApi})
} else { $Report.server_scripts += [pscustomobject]@{name=$ServerName;exists=($null -ne $E)} }
$E=Get-ErpDoc "Client Script" $ClientName
if($Mode -eq "Deploy"){
    $Report.client_scripts += Upsert-ErpDoc "Client Script" $ClientName ([ordered]@{dt="Task";view="Form";enabled=1;script=$ClientScript})
} else { $Report.client_scripts += [pscustomobject]@{name=$ClientName;exists=($null -ne $E)} }
$Report.notes += "Adds product summary and packing scan controls directly on Task while keeping Dispatch Case as source of truth."
$Report | ConvertTo-Json -Depth 40
