// Name: Task-Lock Unaccepted
// DocType: Task
// Enabled: 1
// ---

frappe.ui.form.on('Task', {
    refresh: function(frm) {
        apply_task_accept_edit_lock(frm);
    },
    custom_accepted_by: function(frm) {
        apply_task_accept_edit_lock(frm);
    }
});

function apply_task_accept_edit_lock(frm) {
    if (frm.is_new()) return;

    var roles = frappe.user_roles || [];
    var is_admin = roles.indexOf('System Manager') !== -1 || roles.indexOf('Administrator') !== -1 || frappe.session.user === 'Administrator';
    var accepted_by = frm.doc.custom_accepted_by || '';
    var is_accepted_by_me = accepted_by && accepted_by === frappe.session.user;
    var can_edit = is_admin || is_accepted_by_me;
    console.log('[TaskLock] check', {task: frm.doc.name, accepted_by: accepted_by, user: frappe.session.user, can_edit: can_edit, is_admin: is_admin});
    setTimeout(function() {
        if (can_edit) {
            frm.enable_save();
            frm.set_intro('');
            (frm.fields || []).forEach(function(field) {
                if (field.df && field.df.fieldname && field.df.fieldtype !== 'Section Break' && field.df.fieldtype !== 'Column Break') {
                    frm.set_df_property(field.df.fieldname, 'read_only', 0);
                }
            });

            var editable_fields = [
                'status', 'delivery_status', 'pickup_status', 'driver_handover_note',
                'return_pickup_driver', 'scheduled_return_date', 'approval_outcome', 'approval_note',
                'custom_task_scan_barcode', 'custom_task_scan_qty', 'custom_task_add_item_code',
                'custom_task_add_qty', 'custom_task_add_batch_no', 'custom_task_add_unit_price',
                'new_payment_amount', 'payment_method', 'payment_reference'
            ];
            editable_fields.forEach(function(fieldname) {
                if (frm.fields_dict[fieldname]) {
                    frm.set_df_property(fieldname, 'read_only', 0);
                    frm.toggle_enable(fieldname, true);
                }
            });

            frm.refresh_fields();
            $(frm.wrapper).find('input, textarea, select, .ql-editor, .like-disabled-input').prop('disabled', false).css({'pointer-events': '', 'opacity': '', 'background-color': ''});
            $(frm.wrapper).find('.btn-attach, .btn-open, .grid-add-row, .grid-remove-rows').show();
            // Update gallery mode to editable (only for galleries whose config allows editing)
            if (frm._photoGalleries) { Object.values(frm._photoGalleries).forEach(function(g) { if (g._configEditable) g.setMode('editable'); }); }
        } else {
            frm.disable_save();
            frm.set_intro('You must accept this task before you can edit it. Click <b>Accept / Start Task</b>.', 'yellow');
            (frm.fields || []).forEach(function(field) {
                if (field.df && field.df.fieldname && field.df.fieldtype !== 'Section Break' && field.df.fieldtype !== 'Column Break') {
                    frm.set_df_property(field.df.fieldname, 'read_only', 1);
                }
            });
            frm.refresh_fields();
            $(frm.wrapper).find('input, textarea, select, .ql-editor, .like-disabled-input').prop('disabled', true).css({'pointer-events': 'none', 'opacity': '0.6', 'background-color': '#f5f5f5'});
            $(frm.wrapper).find('.btn-attach, .btn-open, .grid-add-row, .grid-remove-rows').hide();
            // Update gallery mode to readonly
            if (frm._photoGalleries) { Object.values(frm._photoGalleries).forEach(function(g) { g.setMode('readonly'); }); }
        }

    }, 700);
}