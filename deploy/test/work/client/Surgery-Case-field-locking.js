// Name: Surgery-Case-field-locking
// DocType: Surgery Case
// Enabled: 1
// ---

frappe.ui.form.on('Surgery Case', {
    refresh(frm) {
        const s = frm.doc.workflow_state || 'Draft';
        const dispatch_editable = ['Draft', 'Preparing', 'Dispatch Picking'].includes(s);
        const returns_editable  = ['Return Pickup In Transit', 'Returns Verification'].includes(s);
        frm.fields_dict.case_items.grid.update_docfield_property('dispatched_qty',   'read_only', dispatch_editable ? 0 : 1);
        frm.fields_dict.case_items.grid.update_docfield_property('returned_qty',     'read_only', returns_editable  ? 0 : 1);
        frm.fields_dict.case_items.grid.update_docfield_property('lost_damaged_qty', 'read_only', returns_editable  ? 0 : 1);
        frm.fields_dict.case_items.grid.update_docfield_property('used_qty',         'read_only', 1);
        frm.refresh_fields();
    }
});