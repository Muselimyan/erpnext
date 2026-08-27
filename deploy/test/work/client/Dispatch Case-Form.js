// Name: Dispatch Case-Form
// DocType: Dispatch Case
// Enabled: 1
// ---

frappe.ui.form.on("Dispatch Case", {
    refresh: function(frm) {
        frm.set_df_property("customer", "reqd", 0);
        frm.set_df_property("client_location_warehouse", "reqd", 0);
        if (frm.fields_dict.customer) frm.fields_dict.customer.df.reqd = 0;
        if (frm.fields_dict.client_location_warehouse) frm.fields_dict.client_location_warehouse.df.reqd = 0;
        // Hide fields: client, warehouse, item template, notes
        setTimeout(function() {
            $(frm.wrapper).find('[data-fieldname="customer"]').closest('.frappe-control').hide();
            $(frm.wrapper).find('[data-fieldname="client_location_warehouse"]').closest('.frappe-control').hide();
            $(frm.wrapper).find('[data-fieldname="surgery_set_type"]').closest('.frappe-control').hide();
            $(frm.wrapper).find('[data-fieldname="notes"]').closest('.frappe-control').hide();
            // Mobile: hide extra fields
            if (window.innerWidth <= 768) {
                ["allow_items_edit","custom_packing_scan_barcode","custom_packing_scan_qty","custom_packing_scan_result","custom_packing_last_warning","custom_packing_problem_status","custom_packing_problem_summary","custom_problem_alert_sent"].forEach(function(fn) {
                    $(frm.wrapper).find('[data-fieldname="' + fn + '"]').closest('.frappe-control').hide();
                });
                $(frm.wrapper).find('[data-fieldname="tasks_section"]').closest('.form-section').hide();
                $(frm.wrapper).find('[data-fieldname="payment_section"]').closest('.form-section').hide();
                $(frm.wrapper).find('[data-fieldname="se_section"]').closest('.form-section').hide();
            }
        }, 300);
        // --- Items edit lock logic ---
        var APPROVER_EMAILS = [
            "levonaghinyan77@gmail.com",
            "vahe.muselimyan@gmail.com",
            "ghahramanyann@gmail.com",
            "karapetyansev@gmail.com"
        ];
        var isApprover = APPROVER_EMAILS.includes(frappe.session.user)
            || frappe.user_roles.includes("Ops - Directors")
            || frappe.user_roles.includes("System Manager")
            || frappe.session.user === "Administrator";
        var canEdit = isApprover || frm.doc.allow_items_edit;

        // Lock/unlock case_items
        if (frm.fields_dict.case_items) {
            var grid = frm.fields_dict.case_items.grid;
            grid.grid_rows.forEach(function(row) {
                row.docfields.forEach(function(df) {
                    grid.toggle_enable(df.fieldname, canEdit);
                });
            });
            if (canEdit) {
                grid.wrapper.find(".grid-add-row, .grid-remove-rows, .row-check").show();
            } else {
                grid.wrapper.find(".grid-add-row, .grid-remove-rows, .row-check").hide();
            }
        }

        // Only approvers can toggle the checkbox; force-enable on submitted docs
        frm.set_df_property("allow_items_edit", "read_only", isApprover ? 0 : 1);
        if (isApprover && frm.doc.docstatus === 1) {
            frm.enable_save();
        }

        // Style the return_expected checkbox bigger and bold label
        var reCtrl = frm.fields_dict.return_expected;
        if (reCtrl && reCtrl.$wrapper) {
            reCtrl.$wrapper.find("input[type=checkbox]").css({
                width: "18px",
                height: "18px",
                "min-width": "18px",
                "min-height": "18px",
                "accent-color": "#e74c3c",
                cursor: "pointer"
            });
            reCtrl.$wrapper.find(".label-area, .control-label, label").css({
                "font-weight": "700",
                color: "#e74c3c",
                "font-size": "13px"
            });
        }
    },
    allow_items_edit: function(frm) {
        frm.refresh_fields();
        frm.script_manager.trigger("refresh");
    },
    surgery_set_type: function(frm) {
        if (!frm.doc.surgery_set_type) return;
        frappe.call({
            method: "frappe.client.get",
            args: { doctype: "Collection Set", name: frm.doc.surgery_set_type },
            callback: function(r) {
                if (!r.message) return;
                frm.clear_table("case_items");
                (r.message.items || []).forEach(function(row) {
                    var nr = frm.add_child("case_items");
                    nr.item_code = String(row.item || "");
                    nr.dispatched_qty = row.qty || 1;
                    nr.unit_price = row.rate || 0;
                });
                frm.refresh_field("case_items");
            }
        });
    }
});