// Name: Task-Packing Checkboxes
// DocType: Task
// Enabled: 1
// ---

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
            const is_returns_task = (frm.doc.task_kind === "Returns processing / verification");
            const is_restocking_task = (frm.doc.task_kind === "Returns restocking");
            const is_invoice_task = (frm.doc.task_kind === "Invoice preparation / create invoice");
            if (is_returns_task) {
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

function task_product_work_area_render_returns(frm, doc, rows, show_alert) {
    const mobile_mode = task_product_work_area_get_mobile_return_mode();
    let html = `<div class="small text-muted" style="margin-bottom:8px">Source: <b>${frappe.utils.escape_html(doc.name)}</b> Â· Customer: <b>${frappe.utils.escape_html(doc.customer || "")}</b></div>`;
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
    let html = `<div class="small text-muted" style="margin-bottom:8px">Source: <b>${frappe.utils.escape_html(doc.name)}</b> Â· Customer: <b>${frappe.utils.escape_html(doc.customer || "")}</b></div>`;
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
    let html = `<div class="small text-muted" style="margin-bottom:8px">Source: <b>${frappe.utils.escape_html(doc.name)}</b> Â· Customer: <b>${frappe.utils.escape_html(doc.customer || "")}</b></div>`;
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

function task_product_work_area_render_packing(frm, doc, rows, show_alert) {
    let html = `<div class="small text-muted" style="margin-bottom:8px">Source: <b>${frappe.utils.escape_html(doc.name)}</b> Â· Customer: <b>${frappe.utils.escape_html(doc.customer || "")}</b></div>`;
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
            frm.add_custom_button(__("Refresh Product Status"), function() {
                task_product_work_area_refresh(frm, true);
            }, __("Products"));
        }
    },
    dispatch_case(frm) {
        task_product_work_area_refresh(frm, true);
    },
    task_kind(frm) {
        task_product_work_area_refresh(frm, true);
    }
});