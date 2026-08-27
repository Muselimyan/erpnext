// Name: Task - Load Surgical Kit Template
// DocType: Task
// Enabled: 1
// ---

frappe.ui.form.on('Dispatch Case', {
    surgery_set_type: function(frm) {
        if (!frm.doc.surgery_set_type) return;

        // Fetch template details from Collection Set DocType
        frappe.db.get_doc('Collection Set', frm.doc.surgery_set_type)
            .then(template => {
                // Clear existing items in Case Items table
                frm.clear_table('case_items');

                // Check for template items (adjust 'template_items' if Collection Set uses another fieldname)
                let items = template.template_items || template.items;

                if (!items || items.length === 0) {
                    frappe.msgprint(__('Selected template has no items.'));
                    return;
                }

                // Insert items into case_items table
                items.forEach(item => {
                    let child = frm.add_child('case_items');
                    child.item_code = item.item_code;
                    child.item_name = item.item_name;
                    child.dispatched_qty = item.qty || 1; 
                });

                frm.refresh_field('case_items');
                frappe.show_alert({
                    message: __('Template items loaded successfully!'),
                    indicator: 'green'
                });
            });
    }
});