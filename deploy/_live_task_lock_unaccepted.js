frappe.ui.form.on('Task', {
    refresh: function(frm) {
        if (frm.is_new()) return;
        var roles = frappe.user_roles || [];
        if (roles.indexOf('System Manager') !== -1 || roles.indexOf('Administrator') !== -1) return;

        if (frm.doc.custom_accepted_by) {
            frm.enable_save();
            setTimeout(function() {
                $(frm.wrapper).find('input, textarea, select, .ql-editor, .like-disabled-input').prop('disabled', false).css({'pointer-events': '', 'opacity': '', 'background-color': ''});
                $(frm.wrapper).find('.btn-attach, .btn-open, .grid-add-row, .grid-remove-rows').show();
                // Force hide internal fields
                $(frm.wrapper).find('[data-fieldname="custom_is_team_queue_task"]').closest('.frappe-control').hide();
                $(frm.wrapper).find('[data-fieldname="custom_team_notified"]').closest('.frappe-control').hide();
                $(frm.wrapper).find('[data-fieldname="custom_team_queue_status"]').closest('.frappe-control').hide();
            }, 600);
            return;
        }

        frm.disable_save();
        frm.set_intro('You must accept this task before you can edit it. Click <b>Accept / Start Task</b>.', 'yellow');
        setTimeout(function() {
            (frm.fields || []).forEach(function(field) {
                if (field.df && field.df.fieldname && field.df.fieldtype !== 'Section Break' && field.df.fieldtype !== 'Column Break') {
                    frm.set_df_property(field.df.fieldname, 'read_only', 1);
                }
            });
            frm.refresh_fields();
            $(frm.wrapper).find('input, textarea, select, .ql-editor, .like-disabled-input').prop('disabled', true).css({'pointer-events': 'none', 'opacity': '0.6', 'background-color': '#f5f5f5'});
            $(frm.wrapper).find('.btn-attach, .btn-open, .grid-add-row, .grid-remove-rows').hide();
            // Force hide internal fields
            $(frm.wrapper).find('[data-fieldname="custom_is_team_queue_task"]').closest('.frappe-control').hide();
            $(frm.wrapper).find('[data-fieldname="custom_team_notified"]').closest('.frappe-control').hide();
            $(frm.wrapper).find('[data-fieldname="custom_team_queue_status"]').closest('.frappe-control').hide();
        }, 500);
    }
});
