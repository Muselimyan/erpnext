frappe.ui.form.on('Task', {
    onload: function(frm) {
        clean_task_layouts(frm);
    },
    refresh: function(frm) {
        clean_task_layouts(frm);
        fetch_pack_prepare_photo(frm);
    },
    task_kind: function(frm) {
        clean_task_layouts(frm);
        fetch_pack_prepare_photo(frm);
    }
});

function clean_task_layouts(frm) {
    const taskKind = (frm.doc.task_kind || "").toString().toLowerCase().trim();

    // Standardized Task Identification Conditions
    const isOrderEntry = (taskKind === "order entry" || taskKind === "order accepting");
    const isPackPrepare = (taskKind === "pack / prepare items");
    const isDelivery = (taskKind === "delivery" || taskKind === "delivery task");
    const isReturnCall = (taskKind === "return call");
    const isPickupReturns = (taskKind === "pickup returns");
    const isInspectReturns = (taskKind === "returns processing / verification");
    const isInvoicePrep = (taskKind.includes("invoice preparation") || taskKind.includes("create invoice"));
    const isReturnsRestocking = (taskKind === "returns restocking");
    const isDebtCollection = (taskKind === "debt collection");
    const isDebtClosure = (taskKind === "debt closure approval");

    const barcodeLabels = [
        "Scan Product Barcode", "Choose Product", "Scan Qty", 
        "Product Qty", "Batch / LOT", "Unit Price"
    ];

    if (frm.fields_dict) {
        Object.values(frm.fields_dict).forEach(function(field) {
            if (!field || !field.df) return;

            // --- A. TEAM QUEUE FIELDS VISIBILITY ---
            if (
                field.df.fieldname === "team_queue_task" || field.df.label === "Team Queue Task" ||
                field.df.fieldname === "team_queue_role" || field.df.label === "Team Queue Role" ||
                field.df.fieldname === "team_queue_status" || field.df.label === "Team Queue Status" ||
                field.df.fieldname === "team_notified" || field.df.label === "Team Notified"
            ) {
                frm.toggle_display(field.df.fieldname, !isDebtClosure);
            }

            // --- B. BARCODE / PRODUCT FIELDS VISIBILITY ---
            if (field.df.label && barcodeLabels.includes(field.df.label)) {
                if (isOrderEntry || isDelivery || isReturnCall || isPickupReturns || isInvoicePrep || isReturnsRestocking || isDebtCollection || isDebtClosure) {
                    frm.toggle_display(field.df.fieldname, false);
                } else {
                    frm.toggle_display(field.df.fieldname, true);
                }
            }

            // --- C. PHOTOS VISIBILITY ---
            if (field.df.label === "Warehouse Pickup Photo" || field.df.label === "Warehouse Drop-off Photo") {
                if (isOrderEntry || isReturnCall || isInspectReturns || isInvoicePrep || isReturnsRestocking || isDebtCollection || isDebtClosure) {
                    frm.toggle_display(field.df.fieldname, false);
                } else if (isPickupReturns) {
                    if (field.df.label === "Warehouse Pickup Photo") {
                        frm.toggle_display(field.df.fieldname, false);
                    } else {
                        frm.toggle_display(field.df.fieldname, true);
                    }
                } else if (isPackPrepare || isDelivery) {
                    if (field.df.label === "Warehouse Drop-off Photo") {
                        frm.toggle_display(field.df.fieldname, false);
                    } else {
                        frm.toggle_display(field.df.fieldname, true);
                    }
                } else {
                    frm.toggle_display(field.df.fieldname, true);
                }
            }

            // --- D. CUSTOM DELIVERY PHOTO / CONTAINER RENDERING ---
            if (field.df.label === "Delivery Photo") {
                frm.toggle_display(field.df.fieldname, isInspectReturns);
                frm.set_df_property(field.df.fieldname, 'read_only', 1);
            }

            // --- E. DRIVER HANDOVER NOTE ---
            if (field.df.label === "Driver Handover Note" || field.df.fieldname === "driver_handover_note") {
                frm.toggle_display(field.df.fieldname, false);
            }

            // --- F. PRODUCT LINES CHILD TABLE ---
            if (field.df.label === "Product Lines") {
                if (isPackPrepare || isDelivery || isReturnCall || isPickupReturns || isInspectReturns || isInvoicePrep || isReturnsRestocking || isDebtCollection || isDebtClosure) {
                    frm.toggle_display(field.df.fieldname, false);
                } else {
                    frm.toggle_display(field.df.fieldname, true);
                }
            }

            // --- G. ACTIVITY LOG BLOCK ---
            if (field.df.label === "Activity" || field.df.fieldname === "activity") {
                frm.toggle_display(field.df.fieldname, !isReturnCall);
            }

            // --- H. SECTION HEADER MANAGEMENT & RENAMING ---
            if (field.df.fieldtype === "Section Break" && field.df.label === "Barcode Scanning (Optional)") {
                if (isDebtClosure) {
                    field.set_label("Total amount paid and profit");
                } else if (isDebtCollection) {
                    field.set_label("Debt amount and status");
                } else if (isOrderEntry || isDelivery || isReturnCall || isPickupReturns || isInvoicePrep || isReturnsRestocking) {
                    field.set_label("Task Status & Priority");
                } else {
                    field.set_label("Barcode Scanning (Optional)");
                }
            }
        });
    }

    // --- 2. COLUMN DOM ARRANGEMENT MECHANICS ---
    if (frm.fields_dict) {
        let targetField1 = Object.values(frm.fields_dict).find(f => f.df && f.df.label === "Scan Product Barcode");
        let targetField2 = Object.values(frm.fields_dict).find(f => f.df && f.df.label === "Choose Product");
        let targetField3 = Object.values(frm.fields_dict).find(f => f.df && f.df.label === "Status");

        const layoutSnap = (isOrderEntry || isDelivery || isReturnCall || isPickupReturns || isInvoicePrep || isReturnsRestocking);

        if (targetField1 && targetField1.$wrapper && targetField2 && targetField2.$wrapper && targetField3 && targetField3.$wrapper) {
            let col1 = targetField1.$wrapper.closest('.form-column');
            let col2 = targetField2.$wrapper.closest('.form-column');
            let col3 = targetField3.$wrapper.closest('.form-column');

            if (col1.length && col2.length && col3.length) {
                if (isDebtClosure) {
                    col1.show().css({ "display": "block", "flex": "", "max-width": "" });
                    col2.show().css({ "display": "block", "flex": "", "max-width": "" });
                    col3.show().css({ "display": "block", "flex": "", "max-width": "" });

                    let profitField = Object.values(frm.fields_dict).find(f => f.df && f.df.label === "Case Profit");
                    let paidField = Object.values(frm.fields_dict).find(f => f.df && f.df.label === "Total Amount Paid");
                    let statusField = Object.values(frm.fields_dict).find(f => f.df && f.df.label === "Status");
                    let priorityField = Object.values(frm.fields_dict).find(f => f.df && f.df.label === "Priority");

                    if (profitField && profitField.$wrapper) col1.append(profitField.$wrapper);
                    if (paidField && paidField.$wrapper) col1.append(paidField.$wrapper);
                    if (statusField && statusField.$wrapper) col2.append(statusField.$wrapper);
                    if (priorityField && priorityField.$wrapper) col2.append(priorityField.$wrapper);

                } else if (isDebtCollection) {
                    col1.hide();
                    col3.show();
                    col2.show().css({ "display": "", "flex": "0 0 66.666%", "max-width": "66.666%" });
                } else {
                    col1.css({ "display": "" });
                    col2.css({ "display": "", "flex": "", "max-width": "" });
                    col3.css({ "display": "" }).show();
                    layoutSnap ? col1.hide() : col1.show();
                    layoutSnap ? col2.hide() : col2.show();
                }
            }
        }
    }
}

// --- 3. FETCH PACK/PREPARE PHOTO DATA LINK & GALLERY ---
function fetch_pack_prepare_photo(frm) {
    const taskKind = (frm.doc.task_kind || "").toString().toLowerCase().trim();
    const isInspectReturns = (taskKind === "returns processing / verification");

    if (!isInspectReturns || !frm.doc.dispatch_case) return;

    // Find the Pack task for this dispatch case
    frappe.call({
        method: 'frappe.client.get_list',
        args: {
            doctype: 'Task',
            filters: { dispatch_case: frm.doc.dispatch_case, task_kind: 'Pack / prepare items' },
            fields: ['name', 'warehouse_pickup_photo'],
            limit_page_length: 1
        },
        async: true,
        callback: function(r) {
            if (!r || !r.message || !r.message.length) return;
            var packTask = r.message[0];

            // Set delivery photo field if empty
            var targetField = Object.values(frm.fields_dict).find(function(f) {
                return f.df && f.df.label === "Delivery Photo";
            });
            if (targetField && packTask.warehouse_pickup_photo && !frm.doc[targetField.df.fieldname]) {
                frm.doc[targetField.df.fieldname] = packTask.warehouse_pickup_photo;
                frm.refresh_field(targetField.df.fieldname);
            }

            // Fetch ALL image files attached to the Pack task
            frappe.call({
                method: 'frappe.client.get_list',
                args: {
                    doctype: 'File',
                    filters: { attached_to_doctype: 'Task', attached_to_name: packTask.name, is_private: ['in', [0, 1]] },
                    fields: ['file_url', 'file_name'],
                    limit_page_length: 50
                },
                async: true,
                callback: function(fr) {
                    var files = (fr.message || []).filter(function(f) {
                        return /\.(jpg|jpeg|png|gif|webp|bmp|heic|heif)$/i.test(f.file_url || '');
                    });
                    // Remove old preview
                    $('#pack_prepare_preview_wrapper').remove();
                    if (!files.length) return;

                    var html = '<div id="pack_prepare_preview_wrapper" style="margin-top:12px;margin-bottom:12px;padding:10px;border:1px solid #d1d8dd;border-radius:6px;background:#fafbfc;max-width:100%;overflow:hidden;">';
                    html += '<label class="control-label" style="color:#6c757d;font-weight:bold;margin-bottom:8px;display:block;">Pack / Prepare Photos (' + files.length + ')</label>';
                    html += '<div style="display:flex;flex-wrap:wrap;gap:8px;align-items:flex-start;max-width:100%;">';
                    files.forEach(function(f) {
                        var url = f.file_url || '';
                        var title = frappe.utils.escape_html(f.file_name || 'Photo');
                        if (url.indexOf('/private/files/') === 0) {
                            url = '/api/method/frappe.utils.file_manager.download_file?file_url=' + encodeURIComponent(url);
                        }
                        var safeUrl = frappe.utils.escape_html(url);
                        html += '<button type="button" class="btn btn-xs" data-pack-photo-url="' + safeUrl + '" data-pack-photo-title="' + title + '" onclick="window.task_inspect_returns_preview_pack_photo(this)" style="display:block;padding:0;border:0;background:transparent;line-height:0;">';
                        html += '<img src="' + safeUrl + '" title="' + title + '" style="width:76px;height:76px;object-fit:cover;border:1px solid #d1d8dd;border-radius:6px;background:#f8f9fa;cursor:pointer;" />';
                        html += '</button>';
                    });
                    html += '</div><div style="font-size:11px;color:#8d99a6;margin-top:6px;">Tap a photo to preview full size.</div></div>';

                    if (targetField && targetField.$wrapper) {
                        targetField.$wrapper.append(html);
                    } else {
                        // Fallback: append after the form body
                        frm.$wrapper.find('.form-layout').append(html);
                    }
                }
            });
        }
    });
}
