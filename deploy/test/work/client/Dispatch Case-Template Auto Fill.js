// Name: Dispatch Case-Template Auto Fill
// DocType: Dispatch Case
// Enabled: 1
// ---

frappe.ui.form.on("Dispatch Case", {
    custom_select_surgical_kit_template: function(frm) {
        if (!frm.doc.custom_select_surgical_kit_template) {
            return;
        }

        frappe.call({
            method: "frappe.client.get",
            args: {
                doctype: "Surgical Kit Template",
                name: frm.doc.custom_select_surgical_kit_template
            },
            freeze: true,
            freeze_message: __("Loading surgical kit template..."),
            callback: function(r) {
                var template = r.message;
                var items = template && template.template_items ? template.template_items : [];

                if (!items.length) {
                    frappe.msgprint(__("Selected Surgical Kit Template has no items."));
                    return;
                }

                frm.clear_table("case_items");

                items.forEach(function(item) {
                    var row = frm.add_child("case_items");
                    row.item_code = item.item_code;
                    row.item_name = item.item_name;
                    row.dispatched_qty = item.qty || 1;
                });

                frm.refresh_field("case_items");
                frappe.show_alert({
                    message: __("Loaded {0} items from Surgical Kit Template", [items.length]),
                    indicator: "green"
                });
            }
        });
    }
});