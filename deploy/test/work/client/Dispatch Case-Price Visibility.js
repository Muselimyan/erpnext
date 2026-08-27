// Name: Dispatch Case-Price Visibility
// DocType: Dispatch Case
// Enabled: 1
// ---

frappe.ui.form.on("Dispatch Case", {
    refresh(frm) {
        // Roles that can see prices and financial info
        const financial_roles = ["Ops - Accounting", "Ops - Finance", "Ops - Directors", "System Manager"];
        const user_roles = frappe.user_roles || [];
        const has_financial_access = financial_roles.some(role => user_roles.includes(role));
        
        if (!has_financial_access) {
            // Hide Invoice and Payment section
            if (frm.fields_dict.payment_section) {
                frm.fields_dict.payment_section.df.hidden = 1;
                frm.refresh_field("payment_section");
            }
            
            // Hide all fields in payment section
            const payment_fields = [
                "sales_invoice", "prepaid_amount", "prepaid_payment_entry",
                "total_invoice_amount", "total_paid_amount", "outstanding_amount"
            ];
            payment_fields.forEach(function(fieldname) {
                if (frm.fields_dict[fieldname]) {
                    frm.set_df_property(fieldname, "hidden", 1);
                }
            });
            
            // Hide price and discount columns in case_items table
            if (frm.fields_dict.case_items && frm.fields_dict.case_items.grid) {
                const grid = frm.fields_dict.case_items.grid;
                
                // Hide columns
                if (grid.docfields) {
                    grid.docfields.forEach(function(df) {
                        if (df.fieldname === "unit_price" || df.fieldname === "discount_pct") {
                            df.hidden = 1;
                            df.in_list_view = 0;
                        }
                    });
                }
                
                // Refresh grid to apply changes
                grid.refresh();
            }
        }
    }
});

frappe.ui.form.on("Dispatch Case Item", {
    form_render(frm, cdt, cdn) {
        // Hide price fields in grid row detail view
        const financial_roles = ["Ops - Accounting", "Ops - Finance", "Ops - Directors", "System Manager"];
        const user_roles = frappe.user_roles || [];
        const has_financial_access = financial_roles.some(role => user_roles.includes(role));
        
        if (!has_financial_access) {
            const row = locals[cdt][cdn];
            const grid_row = frm.fields_dict.case_items.grid.grid_rows_by_docname[row.name];
            
            if (grid_row && grid_row.docfields) {
                grid_row.docfields.forEach(function(df) {
                    if (df.fieldname === "unit_price" || df.fieldname === "discount_pct") {
                        df.hidden = 1;
                    }
                });
            }
        }
    }
});