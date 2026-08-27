// Name: Dispatch Case-Packing Scan
// DocType: Dispatch Case
// Enabled: 1
// ---

frappe.ui.form.on("Dispatch Case", {
    refresh(frm) {
        if (!frm.is_new()) {
            frm.add_custom_button(__("Scan Packing Barcode"), function() {
                dispatch_case_scan_packing_barcode(frm);
            }, __("Packing"));
            
            // Update visual checklist indicators
            update_packing_checklist_visual(frm);
        }
    },
    custom_packing_scan_barcode(frm) {
        if (frm.doc.custom_packing_scan_barcode) {
            dispatch_case_scan_packing_barcode(frm);
        }
    }
});

frappe.ui.form.on("Dispatch Case Item", {
    case_items_add(frm, cdt, cdn) {
        update_packing_checklist_visual(frm);
    },
    case_items_remove(frm, cdt, cdn) {
        update_packing_checklist_visual(frm);
    }
});

function update_packing_checklist_visual(frm) {
    // Add visual indicators to each row based on packing status
    if (!frm.doc.case_items) return;
    
    frm.doc.case_items.forEach(function(row, idx) {
        const required = row.dispatched_qty || 0;
        const scanned = row.custom_scanned_qty || 0;
        const status = row.custom_packing_status || "Pending";
        
        // Get the row element
        setTimeout(function() {
            const row_elem = frm.fields_dict.case_items.grid.grid_rows_by_docname[row.name];
            if (!row_elem || !row_elem.wrapper) return;
            
            // Remove existing indicators
            row_elem.wrapper.find(".packing-indicator").remove();
            
            // Add indicator based on status
            let indicator_html = "";
            let row_class = "";
            
            if (status === "Complete") {
                indicator_html = '<span class="packing-indicator" style="color: green; font-weight: bold; margin-right: 5px;">âœ“</span>';
                row_class = "packing-complete";
            } else if (status === "Partial") {
                indicator_html = '<span class="packing-indicator" style="color: orange; font-weight: bold; margin-right: 5px;">â—</span>';
                row_class = "packing-partial";
            } else if (status === "Over Scanned") {
                indicator_html = '<span class="packing-indicator" style="color: red; font-weight: bold; margin-right: 5px;">âš </span>';
                row_class = "packing-over";
            } else {
                indicator_html = '<span class="packing-indicator" style="color: gray; font-weight: bold; margin-right: 5px;">â¬œ</span>';
                row_class = "packing-pending";
            }
            
            // Add indicator to the first cell
            const first_cell = row_elem.wrapper.find(".grid-row .data-row .col:first");
            if (first_cell.length > 0 && !first_cell.find(".packing-indicator").length) {
                first_cell.prepend(indicator_html);
            }
            
            // Add background color to row
            row_elem.wrapper.removeClass("packing-complete packing-partial packing-over packing-pending");
            row_elem.wrapper.addClass(row_class);
        }, 100);
    });
    
    // Add CSS for row highlighting
    if (!$("style#packing-checklist-css").length) {
        $("head").append(`
            <style id="packing-checklist-css">
                .packing-complete { background-color: #d4edda !important; }
                .packing-partial { background-color: #fff3cd !important; }
                .packing-over { background-color: #f8d7da !important; }
                .packing-pending { background-color: #f8f9fa !important; }
            </style>
        `);
    }
}

function dispatch_case_scan_packing_barcode(frm) {
    const barcode = (frm.doc.custom_packing_scan_barcode || "").trim();
    const qty = frm.doc.custom_packing_scan_qty || 1;
    if (!barcode) {
        frappe.msgprint(__("Scan or enter a barcode first."));
        return;
    }
    
    // First, check if this item exists in the checklist
    frappe.call({
        method: "frappe.client.get_value",
        args: {
            doctype: "Item",
            filters: { name: barcode },
            fieldname: ["name", "item_name"]
        },
        callback: function(item_r) {
            let item_code = null;
            
            // Try to find item code from barcode
            if (item_r.message) {
                item_code = item_r.message.name;
            } else {
                // Check if it's an item barcode
                frappe.call({
                    method: "frappe.client.get_value",
                    args: {
                        doctype: "Item Barcode",
                        filters: { barcode: barcode },
                        fieldname: "parent"
                    },
                    async: false,
                    callback: function(barcode_r) {
                        if (barcode_r.message) {
                            item_code = barcode_r.message.parent;
                        }
                    }
                });
            }
            
            // Check if item is on the checklist
            let on_checklist = false;
            if (item_code && frm.doc.case_items) {
                on_checklist = frm.doc.case_items.some(function(row) {
                    return row.item_code === item_code;
                });
            }
            
            // If not on checklist, show warning
            if (item_code && !on_checklist) {
                frappe.confirm(
                    __("âš ï¸ This item is NOT on the checklist!<br><br>Item: {0}<br><br>Do you want to add it anyway?", [item_code]),
                    function() {
                        // User confirmed - proceed with scan
                        perform_packing_scan(frm, barcode, qty);
                    },
                    function() {
                        // User cancelled - clear barcode field
                        frm.set_value("custom_packing_scan_barcode", "");
                    }
                );
            } else {
                // Item is on checklist or couldn't determine - proceed
                perform_packing_scan(frm, barcode, qty);
            }
        }
    });
}

function perform_packing_scan(frm, barcode, qty) {
    frappe.call({
        method: "dispatch_case_packing_scan",
        args: { case_name: frm.doc.name, barcode: barcode, qty: qty },
        freeze: true,
        freeze_message: __("Checking packing scan..."),
        callback: function(r) {
            const msg = r.message || {};
            if (msg.warning) {
                frappe.msgprint({ title: __("FEFO Warning"), indicator: "orange", message: msg.warning });
            } else {
                frappe.show_alert({ message: __("Scan accepted"), indicator: "green" });
            }
            frm.reload_doc();
            
            // Update visual checklist after reload
            setTimeout(function() {
                update_packing_checklist_visual(frm);
            }, 500);
        }
    });
}