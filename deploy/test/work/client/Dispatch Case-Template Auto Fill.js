// Name: Dispatch Case-Template Auto Fill
// DocType: Dispatch Case
// Enabled: 0
// ---
//
// DISABLED. This built case_items in the browser -- clear_table, then add_child
// with item_code, item_name and dispatched_qty and NO unit_price -- so every
// line of every applied template landed at a price of zero and went on to be
// packed, delivered and consumed for nothing.
//
// The server endpoint task_apply_template does the same job properly: it
// resolves each line through the same chain as add-product (active tender ->
// customer Item Price -> Standard Selling) and refuses the whole template if any
// line is unpriced. It is already wired to the supported UI at
// Task-Product Work Area.js:985.
//
// Not deleted, because the field trigger (custom_select_surgical_kit_template)
// and the dialog wiring are worth keeping if this is ever reinstated. If it is,
// it must call task_apply_template and must not write case_items directly --
// resolving prices in JavaScript would duplicate business logic that
// AGENTS.md requires to live in one place.

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