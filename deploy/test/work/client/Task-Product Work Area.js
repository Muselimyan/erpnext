// Name: Task-Product Work Area
// DocType: Task
// Enabled: 1
// ---
// Merged from: Task-Product Work Area + Task-Packing Checkboxes (2026-08-31)
// - Scanning/adding functions from Product Work Area
// - Packing checkboxes, returns, restocking, invoice rendering from Packing Checkboxes
// - Single unified event handler (was duplicated across both scripts)

// ═══════════════════════════════════════════════════════════════
// Section A: Scanning & Adding Utilities (from Product Work Area)
// ═══════════════════════════════════════════════════════════════

// Temporary item code from REF barcode scan (was custom_task_add_item_code field)
var pwa_pending_item_code = "";

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
        frm.set_value("custom_task_scan_result", __("LOT/expiry captured: {0}, expiry {1}", [parsed.lot_number, parsed.expiry_date]));
        dialog.hide();
        task_product_work_area_call_packing_scan(frm, lot_barcode, item_code);
    };
    dialog.show();
    dialog.set_value("lot_barcode", "");
    task_product_work_area_focus_dialog_scan(dialog);
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
        if (!pwa_pending_item_code) {
            frm.set_value("custom_task_scan_result", __("Scan the REF/product barcode first, then scan the LOT/expiry barcode."));
            frappe.show_alert({ message: __("Scan REF/product barcode first."), indicator: "red" }, 5);
            task_product_work_area_error_beep();
            frm.set_value("custom_task_scan_barcode", "");
            task_product_work_area_focus_scan(frm);
            return;
        }
        frm.set_value("custom_task_scan_result", __("LOT/expiry captured: {0}, expiry {1}", [parsed.lot_number, parsed.expiry_date]));
        frm.set_value("custom_task_scan_barcode", "");
        task_product_work_area_call_packing_scan(frm, barcode, pwa_pending_item_code);
        return;
    }

    frappe.call({
        method: "task_lookup_product_barcode",
        args: { barcode: barcode },
        callback: function(r) {
            const item_code = r.message && r.message.item_code;
            if (item_code) {
                pwa_pending_item_code = item_code;
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

// ═══════════════════════════════════════════════════════════════
// Section B: Shared Core Functions
// ═══════════════════════════════════════════════════════════════

function task_product_work_area_empty(frm, message, indicator) {
    if (frm.fields_dict.custom_task_product_summary) {
        frm.fields_dict.custom_task_product_summary.$wrapper.html(
            `<div class="alert alert-${indicator || "warning"}">${frappe.utils.escape_html(message)}</div>`
        );
    }
}

function task_product_work_area_refresh(frm, show_alert) {
    const is_product_task = tfv_is_product_task(frm);
    if (!is_product_task) {
        if (frm.fields_dict.custom_task_product_summary) {
            frm.fields_dict.custom_task_product_summary.$wrapper.empty();
        }
        return;
    }
    if (!frm.doc.dispatch_case) {
        if (frm.doc.task_kind === "Order entry") {
            task_product_work_area_empty(frm, "Accept this task to auto-create a Dispatch Case, then add products.", "info");
        } else {
            task_product_work_area_empty(frm, "No Dispatch Case linked yet.", "warning");
        }
        frm.set_value("custom_task_product_warning", "");
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
            const is_order_entry_task = (frm.doc.task_kind === "Order entry");
            // Order Entry always renders editor (even with 0 rows — shows add row)
            if (!rows.length && !is_order_entry_task) {
                task_product_work_area_empty(frm, "No product rows in Dispatch Case.", "warning");
                frm.set_value("custom_task_product_warning", "");
                return;
            }
            const is_returns_task = (frm.doc.task_kind === "Returns processing / verification");
            const is_restocking_task = (frm.doc.task_kind === "Returns restocking");
            const is_invoice_task = (frm.doc.task_kind === "Invoice preparation / create invoice");
            if (is_order_entry_task) {
                task_product_work_area_render_order_entry(frm, doc, rows, show_alert);
            } else if (is_returns_task) {
                task_product_work_area_render_returns(frm, doc, rows, show_alert);
            } else if (is_restocking_task) {
                const returned_rows = rows.filter(function(row) { return flt(row.returned_qty || 0) > 0; });
                if (!returned_rows.length) {
                    task_product_work_area_empty(frm, "No returned product rows to restock for this Dispatch Case.", "warning");
                    frm.set_value("custom_task_product_warning", "No returned product rows to restock for this Dispatch Case.");
                    return;
                }
                task_product_work_area_render_restocking(frm, doc, returned_rows, show_alert);
            } else if (is_invoice_task) {
                const invoice_rows = rows.filter(function(row) { return flt(row.used_qty || 0) > 0 || flt(row.lost_damaged_qty || 0) > 0; });
                if (!invoice_rows.length) {
                    task_product_work_area_empty(frm, "No used or lost/damaged product rows to invoice for this Dispatch Case.", "warning");
                    frm.set_value("custom_task_product_warning", "No used or lost/damaged product rows to invoice for this Dispatch Case.");
                    return;
                }
                task_product_work_area_render_invoice_preparation(frm, doc, invoice_rows, show_alert);
            } else {
                task_product_work_area_render_packing(frm, doc, rows, show_alert);
            }
        }
    });
}

// ═══════════════════════════════════════════════════════════════
// Section C: Rendering Functions (from Packing Checkboxes)
// ═══════════════════════════════════════════════════════════════

function task_product_work_area_render_returns(frm, doc, rows, show_alert) {
    const mobile_mode = task_product_work_area_get_mobile_return_mode();
    let html = `<div class="small text-muted" style="margin-bottom:8px">Source: <b>${frappe.utils.escape_html(doc.name)}</b> · Customer: <b>${frappe.utils.escape_html(doc.customer || "")}</b></div>`;
    html += `<style>
        .task-return-phone-toggle, .task-return-mobile-compact, .task-return-mobile-detail { display: none; }
        @media (max-width: 767px) {
            .task-return-desktop-table { display: none; }
            .task-return-phone-toggle { display: flex; justify-content: space-between; align-items: center; gap: 8px; margin: 8px 0; }
            .task-return-phone-toggle button { padding: 3px 8px; font-size: 12px; }
            .task-return-mobile-compact { display: block; }
            .task-return-mobile-detail { display: none; }
            .task-return-mobile-detail.task-return-active { display: block; }
            .task-return-mobile-compact.task-return-hidden { display: none; }
            .task-return-compact-table { width: 100%; table-layout: fixed; font-size: 12px; }
            .task-return-compact-table th, .task-return-compact-table td { padding: 5px 4px !important; vertical-align: middle !important; }
            .task-return-compact-table th:nth-child(1), .task-return-compact-table td:nth-child(1) { width: 34px; text-align: center; }
            .task-return-compact-table th:nth-child(2), .task-return-compact-table td:nth-child(2) { width: 42%; }
            .task-return-compact-table th:nth-child(3), .task-return-compact-table td:nth-child(3) { width: 25%; }
            .task-return-compact-table th:nth-child(4), .task-return-compact-table td:nth-child(4) { width: 25%; }
            .task-return-compact-item { white-space: normal; word-break: break-word; line-height: 1.2; }
            .task-return-compact-table .form-control { min-width: 0 !important; width: 100%; padding: 4px 5px; }
            .task-return-card { border: 1px solid var(--border-color, #d1d8dd); border-radius: 8px; padding: 10px; margin-bottom: 10px; background: var(--fg-color, #fff); }
            .task-return-card-title { font-weight: 600; margin-bottom: 8px; }
            .task-return-card-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; align-items: end; }
            .task-return-card-grid label { font-size: 12px; color: var(--text-muted, #6c7680); margin-bottom: 3px; }
            .task-return-card-grid .form-control { min-width: 0 !important; width: 100%; }
            .task-return-card-full { grid-column: 1 / -1; }
        }
    </style>`;
    html += `<div class="task-return-phone-toggle"><span class="small text-muted">Phone view: <b>${mobile_mode === 'detail' ? 'Detailed' : 'Compact'}</b></span><button type="button" class="btn btn-xs btn-default" onclick="task_product_work_area_toggle_mobile_return_mode()">${mobile_mode === 'detail' ? 'Use Compact' : 'Use Detailed'}</button></div>`;
    html += `<div class="task-return-desktop-table" style="overflow-x:auto"><table class="table table-bordered table-condensed"><thead><tr>
        <th style="width:70px">Returned?</th><th>Name</th><th>Dispatched</th><th>Returned Qty</th><th>Lost/Damaged</th><th>Used</th><th>Batch/LOT</th><th>Expiry</th>
    </tr></thead><tbody>`;
    let compact_html = `<div class="task-return-mobile-compact ${mobile_mode === 'detail' ? 'task-return-hidden' : ''}"><table class="table table-bordered table-condensed task-return-compact-table"><thead><tr><th>Ret?</th><th>Item</th><th>Returned</th><th>Lost</th></tr></thead><tbody>`;
    let detail_html = `<div class="task-return-mobile-detail ${mobile_mode === 'detail' ? 'task-return-active' : ''}">`;
    rows.forEach(function(row, idx) {
        const dispatched = flt(row.dispatched_qty || 0);
        const returned = flt(row.returned_qty || 0);
        const lost = flt(row.lost_damaged_qty || 0);
        const used = row.used_qty !== undefined && row.used_qty !== null ? flt(row.used_qty) : Math.max(dispatched - returned - lost, 0);
        const checked = returned >= dispatched && lost === 0 && dispatched > 0;
        const checkbox_id = `return_checkbox_${idx}`;
        const compact_checkbox_id = `return_compact_checkbox_${idx}`;
        const detail_checkbox_id = `return_detail_checkbox_${idx}`;
        const escaped_case = frappe.utils.escape_html(frm.doc.dispatch_case);
        const item_label = frappe.utils.escape_html(row.item_name || row.item_code || "");
        html += `<tr data-return-row="${idx}">
            <td class="text-center"><input type="checkbox" id="${checkbox_id}" data-idx="${idx}" ${checked ? 'checked' : ''} onchange="task_product_work_area_toggle_returned(this, '${escaped_case}', ${idx})"></td>
            <td>${item_label}</td>
            <td class="text-right" data-dispatched="${dispatched}">${dispatched}</td>
            <td><input type="number" min="0" step="0.001" class="form-control input-xs task-returned-qty" data-idx="${idx}" value="${returned}" style="min-width:82px" onchange="task_product_work_area_update_return_qty(this, '${escaped_case}', ${idx})"></td>
            <td><input type="number" min="0" step="0.001" class="form-control input-xs task-lost-qty" data-idx="${idx}" value="${lost}" style="min-width:82px" onchange="task_product_work_area_update_return_qty(this, '${escaped_case}', ${idx})"></td>
            <td class="text-right task-used-qty">${used}</td>
            <td>${frappe.utils.escape_html(row.batch_no || "")}</td>
            <td>${frappe.utils.escape_html(row.expiry_date || row.custom_expiry_date || "")}</td>
        </tr>`;
        compact_html += `<tr data-return-row="${idx}">
            <td data-dispatched="${dispatched}"><input type="checkbox" id="${compact_checkbox_id}" data-idx="${idx}" ${checked ? 'checked' : ''} onchange="task_product_work_area_toggle_returned(this, '${escaped_case}', ${idx})"></td>
            <td class="task-return-compact-item">${item_label}</td>
            <td><input type="number" min="0" step="0.001" class="form-control input-xs task-returned-qty" data-idx="${idx}" value="${returned}" onchange="task_product_work_area_update_return_qty(this, '${escaped_case}', ${idx})"></td>
            <td><input type="number" min="0" step="0.001" class="form-control input-xs task-lost-qty" data-idx="${idx}" value="${lost}" onchange="task_product_work_area_update_return_qty(this, '${escaped_case}', ${idx})"><span class="hidden task-used-qty">${used}</span></td>
        </tr>`;
        detail_html += `<div class="task-return-card" data-return-row="${idx}">
            <div class="task-return-card-title">${item_label}</div>
            <div class="task-return-card-grid">
                <div class="task-return-card-full" data-dispatched="${dispatched}"><label><input type="checkbox" id="${detail_checkbox_id}" data-idx="${idx}" ${checked ? 'checked' : ''} onchange="task_product_work_area_toggle_returned(this, '${escaped_case}', ${idx})"> Returned?</label></div>
                <div><label>Returned Qty</label><input type="number" min="0" step="0.001" class="form-control input-xs task-returned-qty" data-idx="${idx}" value="${returned}" onchange="task_product_work_area_update_return_qty(this, '${escaped_case}', ${idx})"></div>
                <div><label>Lost/Damaged</label><input type="number" min="0" step="0.001" class="form-control input-xs task-lost-qty" data-idx="${idx}" value="${lost}" onchange="task_product_work_area_update_return_qty(this, '${escaped_case}', ${idx})"></div>
                <div><label>Used</label><div class="form-control input-xs task-used-qty" style="background:#f8f8f8">${used}</div></div>
                <div><label>Sent</label><div class="form-control input-xs" style="background:#f8f8f8">${dispatched}</div></div>
            </div>
        </div>`;
    });
    html += `</tbody></table></div>`;
    compact_html += `</tbody></table></div>`;
    detail_html += `</div>`;
    html += compact_html + detail_html;
    html += `<div class="small text-muted" style="margin-top:8px"><i>Check Returned? for fully returned items. Edit Returned Qty or Lost/Damaged for partial cases. Values are saved into the linked Dispatch Case.</i></div>`;
    if (frm.fields_dict.custom_task_product_summary) {
        frm.fields_dict.custom_task_product_summary.$wrapper.html(html);
    }
    frm.set_value("custom_task_product_warning", doc.custom_packing_last_warning || doc.custom_packing_problem_summary || "");
    if (show_alert) {
        frappe.show_alert({ message: __("Product summary refreshed"), indicator: "green" });
    }
}

function task_product_work_area_get_mobile_return_mode() {
    try {
        return localStorage.getItem('task_inspect_returns_phone_view') === 'detail' ? 'detail' : 'compact';
    } catch (e) {
        return 'compact';
    }
}

window.task_product_work_area_toggle_mobile_return_mode = function() {
    const next_mode = task_product_work_area_get_mobile_return_mode() === 'detail' ? 'compact' : 'detail';
    try {
        localStorage.setItem('task_inspect_returns_phone_view', next_mode);
    } catch (e) {}
    if (cur_frm) {
        task_product_work_area_refresh(cur_frm, false);
    }
};

function task_product_work_area_render_restocking(frm, doc, rows, show_alert) {
    let html = `<div class="small text-muted" style="margin-bottom:8px">Source: <b>${frappe.utils.escape_html(doc.name)}</b> · Customer: <b>${frappe.utils.escape_html(doc.customer || "")}</b></div>`;
    html += `<div style="overflow-x:auto"><table class="table table-bordered table-condensed"><thead><tr>
        <th>Name</th><th>Returned Qty</th><th>Batch/LOT</th><th>Expiry</th>
    </tr></thead><tbody>`;
    rows.forEach(function(row) {
        const returned = flt(row.returned_qty || 0);
        html += `<tr>
            <td>${frappe.utils.escape_html(row.item_name || row.item_code || "")}</td>
            <td class="text-right">${returned}</td>
            <td>${frappe.utils.escape_html(row.batch_no || "")}</td>
            <td>${frappe.utils.escape_html(row.expiry_date || row.custom_expiry_date || "")}</td>
        </tr>`;
    });
    html += `</tbody></table></div>`;
    html += `<div class="small text-muted" style="margin-top:8px"><i>Restock only the returned quantities shown here from Returns WH back to Main WH.</i></div>`;
    if (frm.fields_dict.custom_task_product_summary) {
        frm.fields_dict.custom_task_product_summary.$wrapper.html(html);
    }
    frm.set_value("custom_task_product_warning", doc.custom_packing_last_warning || doc.custom_packing_problem_summary || "");
    if (show_alert) {
        frappe.show_alert({ message: __("Product summary refreshed"), indicator: "green" });
    }
}

function task_product_work_area_render_invoice_preparation(frm, doc, rows, show_alert) {
    let html = `<div class="small text-muted" style="margin-bottom:8px">Source: <b>${frappe.utils.escape_html(doc.name)}</b> · Customer: <b>${frappe.utils.escape_html(doc.customer || "")}</b></div>`;
    html += `<div style="overflow-x:auto"><table class="table table-bordered table-condensed"><thead><tr>
        <th>Name</th><th>Used Qty</th><th>Lost/Damaged Qty</th><th>Batch/LOT</th><th>Expiry</th>
    </tr></thead><tbody>`;
    rows.forEach(function(row) {
        const used = flt(row.used_qty || 0);
        const lost = flt(row.lost_damaged_qty || 0);
        html += `<tr>
            <td>${frappe.utils.escape_html(row.item_name || row.item_code || "")}</td>
            <td class="text-right">${used}</td>
            <td class="text-right">${lost}</td>
            <td>${frappe.utils.escape_html(row.batch_no || "")}</td>
            <td>${frappe.utils.escape_html(row.expiry_date || row.custom_expiry_date || "")}</td>
        </tr>`;
    });
    html += `</tbody></table></div>`;
    html += `<div class="small text-muted" style="margin-top:8px"><i>Review only used and lost/damaged quantities for invoice preparation.</i></div>`;
    if (frm.fields_dict.custom_task_product_summary) {
        frm.fields_dict.custom_task_product_summary.$wrapper.html(html);
    }
    frm.set_value("custom_task_product_warning", doc.custom_packing_last_warning || doc.custom_packing_problem_summary || "");
    if (show_alert) {
        frappe.show_alert({ message: __("Product summary refreshed"), indicator: "green" });
    }
}

function task_product_work_area_render_order_entry(frm, doc, rows, show_alert) {
    var esc = frappe.utils.escape_html;
    var dc_name = doc.name;
    var is_editable = !frm.is_new()
        && frm.doc.task_kind === "Order entry"
        && frm.doc.dispatch_case
        && frm.doc.status !== "Completed"
        && frm.doc.custom_accepted_by === frappe.session.user;

    var html = '<div class="small text-muted" style="margin-bottom:8px">'
        + 'Dispatch Case: <b>' + esc(dc_name) + '</b>'
        + ' &middot; Customer: <b>' + esc(doc.customer || "") + '</b></div>';

    if (!rows.length && is_editable) {
        html += '<div class="text-muted small" style="margin-bottom:8px">'
            + '<i>No products yet. Use the row below to add items.</i></div>';
    }

    html += '<div style="overflow-x:auto"><table class="table table-bordered table-condensed oe-editor-table">'
        + '<thead><tr>'
        + '<th>Item</th>'
        + '<th style="width:80px">Qty</th>'
        + '<th style="width:100px">Unit Price</th>'
        + '<th style="width:90px">Discount %</th>'
        + '<th style="width:110px">Batch/LOT</th>'
        + (is_editable ? '<th style="width:45px"></th>' : '')
        + '</tr></thead><tbody>';

    rows.forEach(function(row) {
        var qty = flt(row.dispatched_qty || 0);
        var price = flt(row.unit_price || 0);
        var discount = flt(row.discount_pct || 0);
        var batch = row.batch_no || "";
        var rn = esc(row.name);
        if (is_editable) {
            html += '<tr data-row-name="' + rn + '">'
                + '<td>' + esc(row.item_name || row.item_code || "") + '</td>'
                + '<td><input type="number" class="form-control input-xs oe-edit" data-field="dispatched_qty" '
                +     'value="' + qty + '" min="0.001" step="0.001" style="text-align:right"></td>'
                + '<td><input type="number" class="form-control input-xs oe-edit" data-field="unit_price" '
                +     'value="' + price + '" min="0" step="0.01" style="text-align:right"></td>'
                + '<td><input type="number" class="form-control input-xs oe-edit" data-field="discount_pct" '
                +     'value="' + discount + '" min="0" max="100" step="0.1" style="text-align:right"></td>'
                + '<td><input type="text" class="form-control input-xs oe-edit" data-field="batch_no" '
                +     'value="' + esc(batch) + '"></td>'
                + '<td class="text-center"><button type="button" class="btn btn-xs btn-danger oe-remove-btn" '
                +     'data-row-name="' + rn + '" data-item="' + esc(row.item_name || row.item_code || "") + '"'
                +     ' title="Remove">&times;</button></td>'
                + '</tr>';
        } else {
            html += '<tr>'
                + '<td>' + esc(row.item_name || row.item_code || "") + '</td>'
                + '<td class="text-right">' + qty + '</td>'
                + '<td class="text-right">' + (price ? frappe.format(price, {fieldtype: "Currency"}) : "-") + '</td>'
                + '<td class="text-right">' + (discount ? discount + "%" : "-") + '</td>'
                + '<td>' + esc(batch) + '</td>'
                + '</tr>';
        }
    });

    if (is_editable) {
        html += '<tr class="oe-add-row" style="background:#f9f9f9">'
            + '<td><div class="oe-add-item-cell"></div></td>'
            + '<td><input type="number" class="form-control input-xs oe-add-qty" value="1" min="0.001" step="0.001" style="text-align:right"></td>'
            + '<td><input type="number" class="form-control input-xs oe-add-price" value="0" min="0" step="0.01" style="text-align:right"></td>'
            + '<td><input type="number" class="form-control input-xs oe-add-discount" value="0" min="0" max="100" step="0.1" style="text-align:right"></td>'
            + '<td><input type="text" class="form-control input-xs oe-add-batch" placeholder="LOT" style="font-size:12px"></td>'
            + '<td class="text-center"><button type="button" class="btn btn-xs btn-primary oe-add-btn" title="Add product">+</button></td>'
            + '</tr>';
    }

    html += '</tbody></table></div>';
    if (is_editable) {
        html += '<div class="small text-muted"><i>Edit quantities and prices directly &mdash; changes auto-save. Click + to add a new item.</i></div>';
    }

    if (!frm.fields_dict.custom_task_product_summary) return;
    var wrapper = frm.fields_dict.custom_task_product_summary.$wrapper;
    wrapper.html(html);

    if (!is_editable) {
        frm.set_value("custom_task_product_warning", "");
        if (show_alert) frappe.show_alert({ message: __("Product summary refreshed"), indicator: "green" });
        return;
    }

    // ── Attach Frappe Link control for item picker in add row ──
    var item_cell = wrapper.find(".oe-add-item-cell");
    var item_control = frappe.ui.form.make_control({
        df: {
            fieldtype: "Link",
            options: "Item",
            fieldname: "oe_inline_item",
            placeholder: "Search item..."
        },
        parent: item_cell,
        render_input: true,
        only_input: true
    });
    item_control.refresh();
    // Auto-fill price from standard_rate when item selected
    item_control.$input.on("change", function() {
        var item_code = item_control.get_value();
        if (item_code) {
            frappe.db.get_value("Item", item_code, ["standard_rate"], function(v) {
                if (v && v.standard_rate) {
                    wrapper.find(".oe-add-price").val(flt(v.standard_rate));
                }
            });
        }
    });

    // ── Debounced auto-save for existing row edits (800ms) ──
    var save_timer = null;
    wrapper.find(".oe-edit").on("input", function() {
        var input = $(this);
        var tr = input.closest("tr");
        var row_name = tr.attr("data-row-name");
        clearTimeout(save_timer);
        save_timer = setTimeout(function() {
            frappe.call({
                method: "task_update_dispatch_product",
                args: {
                    case_name: dc_name,
                    row_name: row_name,
                    dispatched_qty: tr.find('[data-field="dispatched_qty"]').val(),
                    unit_price: tr.find('[data-field="unit_price"]').val(),
                    discount_pct: tr.find('[data-field="discount_pct"]').val(),
                    batch_no: tr.find('[data-field="batch_no"]').val()
                },
                callback: function(r) {
                    if (r.message && r.message.ok) {
                        frappe.show_alert({ message: __("Saved"), indicator: "green" });
                    }
                }
            });
        }, 800);
    });

    // ── Remove buttons ──
    wrapper.find(".oe-remove-btn").on("click", function() {
        var btn = $(this);
        var row_name = btn.attr("data-row-name");
        var item = btn.attr("data-item");
        frappe.confirm(
            __("Remove {0}?", [item]),
            function() {
                frappe.call({
                    method: "task_remove_dispatch_product",
                    args: { case_name: dc_name, row_name: row_name },
                    freeze: true,
                    freeze_message: __("Removing..."),
                    callback: function(r) {
                        if (r.message && r.message.ok) {
                            frappe.show_alert({ message: __("Removed"), indicator: "green" });
                            task_product_work_area_refresh(frm, false);
                        }
                    }
                });
            }
        );
    });

    // ── Add button ──
    wrapper.find(".oe-add-btn").on("click", function() {
        var item_code = item_control.get_value();
        if (!item_code) {
            frappe.msgprint(__("Choose an item first."));
            return;
        }
        frappe.call({
            method: "task_add_dispatch_product",
            args: {
                task_name: frm.doc.name,
                item_code: item_code,
                qty: wrapper.find(".oe-add-qty").val() || 1,
                batch_no: wrapper.find(".oe-add-batch").val() || "",
                unit_price: wrapper.find(".oe-add-price").val() || 0,
                discount_pct: wrapper.find(".oe-add-discount").val() || 0
            },
            freeze: true,
            freeze_message: __("Adding product..."),
            callback: function(r) {
                if (r.message && r.message.ok) {
                    frappe.show_alert({ message: __("Product added"), indicator: "green" });
                    task_product_work_area_refresh(frm, false);
                }
            }
        });
    });

    frm.set_value("custom_task_product_warning", "");
    if (show_alert) {
        frappe.show_alert({ message: __("Product summary refreshed"), indicator: "green" });
    }
}

function task_product_work_area_render_packing(frm, doc, rows, show_alert) {
    let html = `<div class="small text-muted" style="margin-bottom:8px">Source: <b>${frappe.utils.escape_html(doc.name)}</b> · Customer: <b>${frappe.utils.escape_html(doc.customer || "")}</b></div>`;
    html += `<div style="overflow-x:auto"><table class="table table-bordered table-condensed"><thead><tr>
        <th style="width:60px">Packed?</th><th>Name</th><th>Required</th><th>Scanned</th><th>Missing</th><th>Batch/LOT</th><th>Expiry</th><th>Status</th><th>Warning / Problem</th>
    </tr></thead><tbody>`;
    rows.forEach(function(row, idx) {
        const required = flt(row.dispatched_qty || 0);
        const scanned = flt(row.custom_scanned_qty || 0);
        const remaining = row.custom_remaining_qty !== undefined && row.custom_remaining_qty !== null ? flt(row.custom_remaining_qty) : Math.max(required - scanned, 0);
        const warn = row.custom_fefo_warning || row.custom_problem_reason || "";
        const status = row.custom_packing_status || (remaining <= 0 ? "Complete" : scanned > 0 ? "Partial" : "Pending");
        const is_packed = (status === "Complete" || status === "Over Scanned");
        const checkbox_id = `pack_checkbox_${idx}`;
        html += `<tr>
            <td class="text-center"><input type="checkbox" id="${checkbox_id}" data-idx="${idx}" ${is_packed ? 'checked' : ''} onchange="task_product_work_area_toggle_packed(this, '${frappe.utils.escape_html(frm.doc.dispatch_case)}', ${idx})"></td>
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
    html += `<div class="small text-muted" style="margin-top:8px"><i>Tip: Check the box when you've packed the item. The Scanned column will update to match Required and Missing will become 0.</i></div>`;
    if (frm.fields_dict.custom_task_product_summary) {
        frm.fields_dict.custom_task_product_summary.$wrapper.html(html);
    }
    frm.set_value("custom_task_product_warning", doc.custom_packing_last_warning || doc.custom_packing_problem_summary || "");
    if (show_alert) {
        frappe.show_alert({ message: __("Product summary refreshed"), indicator: "green" });
    }
}

// ═══════════════════════════════════════════════════════════════
// Section D: Interactive Handlers (window.* for inline onclick)
// ═══════════════════════════════════════════════════════════════

window.task_product_work_area_toggle_returned = function(checkbox, case_name, idx) {
    const row = $(checkbox).closest('[data-return-row]');
    const dispatched = flt(row.find('[data-dispatched]').attr('data-dispatched') || 0);
    const returned = checkbox.checked ? dispatched : 0;
    row.find('.task-returned-qty').val(returned);
    row.find('.task-lost-qty').val(0);
    task_product_work_area_save_return_row(case_name, idx, returned, 0, checkbox);
};

window.task_product_work_area_update_return_qty = function(input, case_name, idx) {
    const row = $(input).closest('[data-return-row]');
    const returned = flt(row.find('.task-returned-qty').val() || 0);
    const lost = flt(row.find('.task-lost-qty').val() || 0);
    task_product_work_area_save_return_row(case_name, idx, returned, lost, input);
};

function task_product_work_area_save_return_row(case_name, idx, returned, lost, control) {
    frappe.call({
        method: "task_update_return_item_quantities",
        args: {
            case_name: case_name,
            item_idx: idx,
            returned_qty: returned,
            lost_damaged_qty: lost
        },
        freeze: true,
        freeze_message: __("Saving return quantities..."),
        callback: function(r) {
            const msg = r.message || {};
            if (msg.ok) {
                const row = $(control).closest('[data-return-row]');
                row.find('.task-used-qty').text(msg.used_qty);
                row.find('.task-returned-qty').val(msg.returned_qty);
                row.find('.task-lost-qty').val(msg.lost_damaged_qty);
                row.find('input[type="checkbox"]').prop('checked', flt(msg.returned_qty) >= flt(msg.dispatched_qty) && flt(msg.lost_damaged_qty) === 0 && flt(msg.dispatched_qty) > 0);
                frappe.show_alert({ message: __("Saved return quantities: {0}", [msg.item_code]), indicator: "green" });
                const frm = cur_frm;
                if (frm) {
                    task_product_work_area_refresh(frm, false);
                }
            }
        },
        error: function() {
            frappe.show_alert({ message: __("Failed to save return quantities"), indicator: "red" });
            const frm = cur_frm;
            if (frm) {
                task_product_work_area_refresh(frm, false);
            }
        }
    });
}

window.task_product_work_area_toggle_packed = function(checkbox, case_name, idx) {
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
                const frm = cur_frm;
                if (frm) {
                    task_product_work_area_refresh(frm, false);
                }
            }
        },
        error: function() {
            checkbox.checked = !packed;
            frappe.show_alert({ message: __("Failed to update packing status"), indicator: "red" });
        }
    });
};

// ═══════════════════════════════════════════════════════════════
// Section E: Unified Event Handler
// ═══════════════════════════════════════════════════════════════

frappe.ui.form.on("Task", {
    refresh(frm) {
        task_product_work_area_refresh(frm);
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
    order_template(frm) {
        if (!frm.doc.order_template) return;
        if (frm.doc.task_kind !== "Order entry") return;
        if (!frm.doc.dispatch_case) {
            frappe.msgprint(__("Create or link a Dispatch Case first."));
            frm.set_value("order_template", "");
            return;
        }
        var apply_fn = function() {
            frappe.call({
                method: "task_apply_template",
                args: {
                    task_name: frm.doc.name,
                    dispatch_case: frm.doc.dispatch_case,
                    template_name: frm.doc.order_template
                },
                freeze: true,
                freeze_message: __("Applying template..."),
                callback: function(r) {
                    var msg = r.message || {};
                    if (msg.ok) {
                        frappe.show_alert({ message: __("Template applied: {0} items", [msg.count || 0]), indicator: "green" });
                        task_product_work_area_refresh(frm, false);
                    }
                }
            });
        };
        // Check if DC already has items — confirm before replacing
        frappe.call({
            method: "frappe.client.get_count",
            args: { doctype: "Dispatch Case Item", filters: { parent: frm.doc.dispatch_case } },
            callback: function(r) {
                var count = cint(r.message);
                if (count > 0) {
                    frappe.confirm(
                        __("This will replace the existing {0} item(s) in the Dispatch Case. Continue?", [count]),
                        apply_fn
                    );
                } else {
                    apply_fn();
                }
            }
        });
    }
});
