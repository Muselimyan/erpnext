// Name: Task-Product Lines Display
// DocType: Task
// Enabled: 0
// DISABLED: Superseded by Task-Create Dispatch Case Items.js which uses
// the server-side task_create_dispatch_case method. This script used
// client-side frappe.client.insert with a hardcoded wrong warehouse default.
// ---

frappe.ui.form.on("Task", {
    refresh: function(frm) {
        if (frm.doc.task_kind === "Account details") return;
        // Show "Create Dispatch Case" button immediately for Order entry tasks with customer
        if (frm.doc.task_kind === "Order entry" && frm.doc.customer) {
            frm.add_custom_button(__("Create Dispatch Case"), function() {
                // Save task first if it is new or has unsaved changes
                if (frm.is_new() || frm.is_dirty()) {
                    frappe.msgprint(__("Saving task first..."));
                    frm.save().then(function() {
                        create_dispatch_case_from_task(frm);
                    });
                } else {
                    create_dispatch_case_from_task(frm);
                }
            }, __("Actions"));
        }
    }
});

// Function to create Dispatch Case from Task (no product lines needed)
function create_dispatch_case_from_task(frm) {
    frappe.confirm(
        __("Create a new Dispatch Case from this Task? You will add items in the Dispatch Case."),
        function() {
            // Create new Dispatch Case with auto-filled fields from Task
            frappe.call({
                method: "frappe.client.insert",
                args: {
                    doc: {
                        doctype: "Dispatch Case",
                        customer: frm.doc.customer || "",
                        client_location_warehouse: "Main - Inmed",
                        surgery_date: frm.doc.exp_end_date || frappe.datetime.nowdate(),
                        notes: frm.doc.description || ("Created from Task: " + frm.doc.subject)
                    }
                },
                callback: function(r) {
                    if (r.message) {
                        let dispatch_case = r.message.name;
                        
                        // Link Task to Dispatch Case
                        frappe.call({
                            method: "frappe.client.set_value",
                            args: {
                                doctype: "Task",
                                name: frm.doc.name,
                                fieldname: "dispatch_case",
                                value: dispatch_case
                            },
                            callback: function() {
                                frappe.show_alert({
                                    message: __("Dispatch Case {0} created. Add items now.", [dispatch_case]),
                                    indicator: "green"
                                });
                                
                                // Open the new Dispatch Case
                                frappe.set_route("Form", "Dispatch Case", dispatch_case);
                                
                                // Auto-reload after 500ms to prevent stale document errors
                                setTimeout(function() {
                                    if (cur_frm && cur_frm.doctype === "Dispatch Case" && cur_frm.doc.name === dispatch_case) {
                                        cur_frm.reload_doc();
                                    }
                                }, 500);
                            }
                        });
                    }
                }
            });
        }
    );
}
