// Name: Dispatch Case-Simplify for Order Creation
// DocType: Dispatch Case
// Enabled: 1
// ---

frappe.ui.form.on("Dispatch Case", {
    refresh(frm) {
        // Only simplify for Order Creation team
        const order_creation_roles = ["Ops - Order Creating"];
        const user_roles = frappe.user_roles || [];
        const is_order_creation = order_creation_roles.some(role => user_roles.includes(role));
        
        // Don't hide for financial/director roles
        const privileged_roles = ["Ops - Accounting", "Ops - Finance", "Ops - Directors", "System Manager"];
        const is_privileged = privileged_roles.some(role => user_roles.includes(role));
        
        if (is_order_creation && !is_privileged) {
            // Hide Linked Tasks section
            if (frm.fields_dict.tasks_section) {
                frm.fields_dict.tasks_section.df.hidden = 1;
                frm.refresh_field("tasks_section");
            }
            
            // Hide all task link fields
            const task_fields = [
                "order_entry_task", "discount_approval_task", "discount_approval_status",
                "pack_task", "delivery_task", "return_waiting_task", "return_pickup_task",
                "returns_inspection_task", "restock_task", "invoice_task"
            ];
            task_fields.forEach(function(fieldname) {
                if (frm.fields_dict[fieldname]) {
                    frm.set_df_property(fieldname, "hidden", 1);
                }
            });
            
            // Hide Stock Entries section
            if (frm.fields_dict.se_section) {
                frm.fields_dict.se_section.df.hidden = 1;
                frm.refresh_field("se_section");
            }
            
            // Hide all stock entry fields
            const se_fields = [
                "dispatch_stock_entry", "delivery_stock_entry", "consumption_stock_entry",
                "return_pickup_stock_entry", "return_receive_stock_entry", "restock_stock_entry"
            ];
            se_fields.forEach(function(fieldname) {
                if (frm.fields_dict[fieldname]) {
                    frm.set_df_property(fieldname, "hidden", 1);
                }
            });
            
            // Hide Photos section
            if (frm.fields_dict.photo_section) {
                frm.fields_dict.photo_section.df.hidden = 1;
                frm.refresh_field("photo_section");
            }
            
            // Hide photo fields
            const photo_fields = ["delivery_photo", "return_dropoff_photo"];
            photo_fields.forEach(function(fieldname) {
                if (frm.fields_dict[fieldname]) {
                    frm.set_df_property(fieldname, "hidden", 1);
                }
            });
            
            // Hide packing scan fields (these are custom fields)
            const packing_fields = [
                "custom_packing_scan_barcode", "custom_packing_scan_qty", 
                "custom_packing_scan_result", "custom_packing_last_warning",
                "custom_packing_problem_status", "custom_packing_problem_summary",
                "custom_problem_alert_sent"
            ];
            packing_fields.forEach(function(fieldname) {
                if (frm.fields_dict[fieldname]) {
                    frm.set_df_property(fieldname, "hidden", 1);
                }
            });
            
            // Hide packing-related columns in case_items table
            if (frm.fields_dict.case_items && frm.fields_dict.case_items.grid) {
                const grid = frm.fields_dict.case_items.grid;
                
                if (grid.docfields) {
                    const hide_columns = [
                        "custom_packing_status", "custom_scanned_qty", "custom_remaining_qty",
                        "custom_last_scanned_barcode", "custom_last_scan_at", "custom_last_scanned_by",
                        "custom_fefo_warning", "custom_scan_note", "custom_problem_reason",
                        "custom_problem_alert_sent", "returned_qty", "lost_damaged_qty", "used_qty"
                    ];
                    
                    grid.docfields.forEach(function(df) {
                        if (hide_columns.includes(df.fieldname)) {
                            df.hidden = 1;
                            df.in_list_view = 0;
                        }
                    });
                }
                
                grid.refresh();
            }
            
            // Show a helpful message
            if (frm.is_new()) {
                frappe.show_alert({
                    message: __("Form simplified for Order Creation. Fill in Return Expected, verify items, and Submit!"),
                    indicator: "blue"
                });
            }
        }
    }
});