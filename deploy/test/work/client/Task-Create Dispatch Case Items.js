// Name: Task-Create Dispatch Case Items
// DocType: Task
// Enabled: 1
// ---

function _task_create_dispatch(frm) {
    frappe.call({
        method: "task_create_dispatch_case",
        args: { task_name: frm.doc.name },
        freeze: true,
        freeze_message: __("Creating Dispatch Case..."),
        callback: function(r) {
            var msg = r.message || {};
            if (msg.dispatch_case) {
                frappe.show_alert({ message: __("Dispatch Case created"), indicator: "green" });
                frm.reload_doc();
            }
        }
    });
}

function _add_create_dispatch_btn(frm) {
    frm.add_custom_button(__("Create Dispatch Case"), function() {
        if (!frm.doc.customer) {
            frappe.msgprint(__("Select Customer on this Task first."));
            return;
        }
        if (frm.dirty()) {
            frm.save().then(function() { _task_create_dispatch(frm); });
        } else {
            _task_create_dispatch(frm);
        }
    });
    frm.change_custom_button_type(__("Create Dispatch Case"), null, "primary");
}

frappe.ui.form.on("Task", {
    refresh(frm) {
        var dispatchKinds = [
            "Pack / prepare items", "Dispatch picking / hand-off", "Delivery",
            "Pickup Returns", "Return drop-off at warehouse", "Returns processing / verification",
            "Returns restocking", "Invoice preparation / create invoice", "Debt Collection", "Discount Approval"
        ];
        var isDispatchWork = frm.doc.dispatch_case || dispatchKinds.includes(frm.doc.task_kind);

        // Order Entry tasks
        if (!frm.is_new() && frm.doc.task_kind === "Order entry") {
            frm.set_df_property("subject", "reqd", 0);
            if (frm.doc.dispatch_case) {
                frm.add_custom_button(__("Open Dispatch Case"), function() {
                    frappe.set_route("Form", "Dispatch Case", frm.doc.dispatch_case);
                });
            } else if (frm.doc.custom_accepted_by) {
                _add_create_dispatch_btn(frm);
            }
            return;
        }

        // Other task kinds
        if (!frm.is_new() && isDispatchWork) {
            if (frm.doc.dispatch_case) {
                frm.add_custom_button(__("Open Dispatch Case / Items"), function() {
                    frappe.set_route("Form", "Dispatch Case", frm.doc.dispatch_case);
                }, __("Dispatch & Packing Work"));
            } else {
                frm.dashboard.add_comment(
                    __("This task needs a <b>Dispatch Case / Packing Items</b> document before item rows, scanning, batch/LOT, expiry, and missing quantities can be managed."),
                    "orange", true
                );
                frm.add_custom_button(__("Create Dispatch Case / Items"), function() {
                    if (!frm.doc.customer) {
                        frappe.msgprint(__("Select Customer on this Task first."));
                        return;
                    }
                    _task_create_dispatch(frm);
                }, __("Dispatch & Packing Work"));
            }
        }
    },

});