// Name: Dispatch Case Item-Auto Fill Item Name
// DocType: Dispatch Case Item
// Enabled: 1
// ---

frappe.ui.form.on("Dispatch Case Item", {
    item_code: function(frm, cdt, cdn) {
        let row = locals[cdt][cdn];
        if (row.item_code && !row.item_name) {
            // Fetch item name from Item master
            frappe.db.get_value("Item", row.item_code, "item_name", function(r) {
                if (r && r.item_name) {
                    frappe.model.set_value(cdt, cdn, "item_name", r.item_name);
                }
            });
        }
    }
});