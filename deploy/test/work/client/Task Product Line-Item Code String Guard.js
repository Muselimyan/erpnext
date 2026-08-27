// Name: Task Product Line-Item Code String Guard
// DocType: Task
// Enabled: 1
// ---

frappe.ui.form.on("Task Product Line", {
    item_code: function(frm, cdt, cdn) {
        var row = locals[cdt][cdn];
        if (row && row.item_code !== undefined && row.item_code !== null) {
            row.item_code = String(row.item_code);
        }
    },
    item_name: function(frm, cdt, cdn) {
        var row = locals[cdt][cdn];
        if (row && row.item_name !== undefined && row.item_name !== null) {
            row.item_name = String(row.item_name);
        }
    }
});

frappe.ui.form.on("Task", {
    validate: function(frm) {
        (frm.doc.custom_product_lines || []).forEach(function(row) {
            if (row.item_code !== undefined && row.item_code !== null) {
                row.item_code = String(row.item_code);
            }
            if (row.item_name !== undefined && row.item_name !== null) {
                row.item_name = String(row.item_name);
            }
        });
        frm.refresh_field("custom_product_lines");
    }
});