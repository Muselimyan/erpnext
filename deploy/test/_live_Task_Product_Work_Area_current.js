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

function task_product_work_area_focus_dialog_scan(dialog) {
    setTimeout(() => {
        let input = dialog.$wrapper.find('[data-fieldname="lot_barcode"] input:visible').first();
        if (input.length) {
            input.val("").focus();
            setTimeout(() => input.focus(), 100);
        }
    }, 250);
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

function task_product_work_area_call_packing_scan(frm, barcode, item_code_override) {
    frappe.call({
        method: "dispatch_case_packing_scan",
        args: {
            case_name: frm.doc.dispatch_case,
            barcode: barcode,
            qty: frm.doc.custom_task_scan_qty || 1,
            item_code_override: item_code_override || ""
        },
        freeze: true,
        freeze_message: __("Checking packing scan..."),
        callback: function(r) {
            const msg = r.message || {};
            if (msg.warning) {
                frappe.msgprint({ title: __("FEFO Warning"), indicator: "orange", message: msg.warning });
            } else {
                frappe.show_alert({ message: __("Scan accepted"), indicator: "green" });
            }
            frm.set_value("custom_task_scan_result", __("Scanned {0}. Batch/LOT: {1}. Expiry: {2}", [msg.item_code || item_code_override || "", msg.batch_no || "", msg.expiry_date || ""]));
            frm.set_value("custom_task_scan_barcode", "");
            task_product_work_area_refresh(frm, false);
            task_product_work_area_focus_scan(frm);
        },
        error: function() {
            task_product_work_area_error_beep();
            frm.set_value("custom_task_scan_barcode", "");
            task_product_work_area_focus_scan(frm);
        }
    });
}

function task_product_work_area_open_lot_dialog(frm, item_code) {
    let dialog = new frappe.ui.Dialog({
        title: __("Scan LOT / Expiry Barcode for {0}", [item_code]),
        fields: [
            { fieldname: "lot_barcode", label: __("Scan LOT / Expiry Barcode"), fieldtype: "Data" },
            { fieldname: "lot_preview", label: __("Detected LOT / Expiry"), fieldtype: "Small Text", read_only: 1 }
        ]
    });
    dialog.fields_dict.lot_barcode.df.onchange = function() {
        const lot_barcode = (dialog.get_value("lot_barcode") || "").trim();
        if (!lot_barcode) return;
        const parsed = task_product_work_area_parse_gs1(lot_barcode);
        if (!parsed) {
            dialog.set_value("lot_preview", __("Invalid GS1 LOT barcode."));
            frappe.show_alert({ message: __("Invalid GS1 LOT barcode."), indicator: "red" }, 5);
            task_product_work_area_error_beep();
            dialog.set_value("lot_barcode", "");
            task_product_work_area_focus_dialog_scan(dialog);
            return;
        }
        dialog.set_value("lot_preview", __("LOT: {0}, Expiry: {1}", [parsed.lot_number, parsed.expiry_date]));
        frm.set_value("custom_task_add_batch_no", parsed.lot_number);
        frm.set_value("custom_task_scan_result", __("LOT/expiry captured: {0}, expiry {1}", [parsed.lot_number, parsed.expiry_date]));
        dialog.hide();
        task_product_work_area_call_packing_scan(frm, lot_barcode, item_code);
    };
    dialog.show();
    dialog.set_value("lot_barcode", "");
    task_product_work_area_focus_dialog_scan(dialog);
}

frappe.ui.form.on("Task", {
    refresh(frm) {
        if (frm.doc.task_kind === "Account details") return;
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
            let html = `<div class="small text-muted" style="margin-bottom:8px">Source: <b>${frappe.utils.escape_html(doc.name)}</b> ÃÂÃÂÃÂÃÂ· Customer: <b>${frappe.utils.escape_html(doc.customer || "")}</b></div>`;
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
        task_product_work_area_call_packing_scan(frm, barcode, frm.doc.custom_task_add_item_code);
        return;
    }

    frappe.call({
        method: "task_lookup_product_barcode",
        args: { barcode: barcode },
        callback: function(r) {
            const item_code = r.message && r.message.item_code;
        if (item_code) {
            frm.set_value("custom_task_add_item_code", item_code);
            frappe.db.get_value("Item", item_code, ["has_batch_no", "has_expiry_date"], function(v) {
                frm.set_value("custom_task_scan_barcode", "");
                if (v && (v.has_batch_no || v.has_expiry_date)) {
                    frm.set_value("custom_task_scan_result", __("Product selected from REF barcode: {0}. Scan the LOT/expiry barcode in the popup.", [item_code]));
                    frappe.show_alert({ message: __("Product selected. Scan LOT/expiry barcode now."), indicator: "green" });
                    task_product_work_area_open_lot_dialog(frm, item_code);
                } else {
                    frm.set_value("custom_task_scan_result", __("Product selected from REF barcode: {0}.", [item_code]));
                    task_product_work_area_call_packing_scan(frm, barcode, item_code);
                }
            });
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