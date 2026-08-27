// Name: Dispatch Case-Item Code String Guard
// DocType: Dispatch Case
// Enabled: 1
// ---

function dispatch_case_stringify_item_codes(frm) {
    (frm.doc.case_items || []).forEach(function(row) {
        if (row.item_code !== undefined && row.item_code !== null) {
            row.item_code = String(row.item_code);
        }
        if (row.item_name !== undefined && row.item_name !== null) {
            row.item_name = String(row.item_name);
        }
    });
}

frappe.ui.form.on("Dispatch Case", {
    before_save: function(frm) {
        dispatch_case_stringify_item_codes(frm);
    },
    validate: function(frm) {
        dispatch_case_stringify_item_codes(frm);
        frm.refresh_field("case_items");
    }
});

frappe.ui.form.on("Dispatch Case Item", {
    item_code: function(frm, cdt, cdn) {
        var row = locals[cdt][cdn];
        if (row && row.item_code !== undefined && row.item_code !== null) {
            row.item_code = String(row.item_code);
        }
    },
    case_items_add: function(frm) {
        dispatch_case_stringify_item_codes(frm);
    }
});