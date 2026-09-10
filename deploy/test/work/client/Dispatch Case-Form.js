// Name: Dispatch Case-Form
// DocType: Dispatch Case
// Enabled: 1
// ---
// Simplified for v4 redesign: removed allow_items_edit checkbox logic,
// hardcoded approver emails, and custom lock/unlock. Frappe's native
// allow_on_submit fields + Version history handle editing. The server
// script Dispatch-Case-before-save-lock-submitted.py restricts edits
// on submitted DCs to Directors/admins.

frappe.ui.form.on("Dispatch Case", {
    refresh: function(frm) {
        // Remove required flags (filled by Task-side sync)
        frm.set_df_property("customer", "reqd", 0);
        frm.set_df_property("client_location_warehouse", "reqd", 0);
        if (frm.fields_dict.customer) frm.fields_dict.customer.df.reqd = 0;
        if (frm.fields_dict.client_location_warehouse) frm.fields_dict.client_location_warehouse.df.reqd = 0;

        // Hide header fields (customer/warehouse/notes shown inline on items)
        setTimeout(function() {
            $(frm.wrapper).find('[data-fieldname="customer"]').closest('.frappe-control').hide();
            $(frm.wrapper).find('[data-fieldname="client_location_warehouse"]').closest('.frappe-control').hide();
            $(frm.wrapper).find('[data-fieldname="notes"]').closest('.frappe-control').hide();
            // Mobile: hide sections that clutter the small screen
            if (window.innerWidth <= 768) {
                $(frm.wrapper).find('[data-fieldname="tasks_section"]').closest('.form-section').hide();
                $(frm.wrapper).find('[data-fieldname="payment_section"]').closest('.form-section').hide();
                $(frm.wrapper).find('[data-fieldname="se_section"]').closest('.form-section').hide();
            }
        }, 300);

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
    }
});