// Name: Task-Team Queue
// DocType: Task
// Enabled: 1
// ---

frappe.listview_settings['Task'] = frappe.listview_settings['Task'] || {};
frappe.listview_settings['Task'].hide_name_column = true;
var _origRefresh = frappe.listview_settings['Task'].refresh;
frappe.listview_settings['Task'].refresh = function(listview) {
    if (_origRefresh) _origRefresh(listview);
    // Define QuickEntryForm override once
    if (!frappe.ui.form.TaskQuickEntryForm) {
        frappe.ui.form.TaskQuickEntryForm = class extends frappe.ui.form.QuickEntryForm {
            get_variant_fields() {
                return [
                    { fieldname: "quick_subject", label: __("Subject"), fieldtype: "Data", reqd: 0, description: "Optional - leave blank for auto-generated ID" },
                    { fieldname: "quick_products", label: __("Products"), fieldtype: "Small Text", reqd: 0, description: "Type product names/info here" },
                    { fieldname: "quick_customer", label: __("Customer"), fieldtype: "Small Text", reqd: 0, description: "Customer name and contact info" },
                    { fieldname: "quick_date", label: __("Date"), fieldtype: "Small Text", reqd: 0, description: "When this task should be done" },
                    { fieldname: "quick_notes", label: __("Notes"), fieldtype: "Small Text", reqd: 0, description: "Additional info (optional)" }
                ];
            }
            render_dialog() {
                this.mandatory = this.get_variant_fields();
                super.render_dialog();
                this.dialog.$wrapper.find("textarea").css({
                    "min-height": "38px", "height": "38px", "overflow": "hidden", "resize": "none"
                }).on("input", function() {
                    this.style.height = "38px";
                    this.style.height = this.scrollHeight + "px";
                });
            }
            register_primary_action() {
                var me = this;
                this.dialog.set_primary_action(__("Save"), function() {
                    me.dialog.hide();
                    var products = me.dialog.get_value("quick_products") || "";
                    var customer = me.dialog.get_value("quick_customer") || "";
                    var dateInfo = me.dialog.get_value("quick_date") || "";
                    var notes = me.dialog.get_value("quick_notes") || "";
                    var subject = me.dialog.get_value("quick_subject") || "";
                    var descParts = [];
                    if (products) descParts.push("Products: " + products);
                    if (customer) descParts.push("Customer: " + customer);
                    if (dateInfo) descParts.push("Date: " + dateInfo);
                    if (notes) descParts.push("Notes: " + notes);
                    var description = descParts.join("<br>");
                    frappe.call({
                        method: "frappe.client.save",
                        args: { doc: JSON.stringify({ doctype: "Task", subject: subject, description: description, task_kind: "Order entry", status: "Open", custom_team_queue_role: "Ops - Order Creating", custom_assigned_to: "" }) },
                        callback: function(r) {
                            if (r && r.message) {
                                frappe.show_alert({message: __("Task {0} created", [r.message.name]), indicator: "green"});
                                frappe.set_route("Form", "Task", r.message.name);
                            }
                        },
                        error: function() {
                            frappe.msgprint(__("Error creating task. Please try Edit Full Form."));
                        }
                    });
                });
            }
        };
    }
};