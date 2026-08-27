// Name: Task-Hide Sidebar Assignment
// DocType: Task
// Enabled: 0
// ---

frappe.ui.form.on("Task", {
    refresh(frm) {
        // Hide ALL assignment UI - sidebar and any assign_to fields
        if (frm.sidebar && frm.sidebar.assigned_to_me) {
            frm.sidebar.assigned_to_me.wrapper.hide();
        }
        
        // Hide all assignment-related UI everywhere
        setTimeout(function() {
            // Hide sidebar sections
            $('[data-fieldname="assign_to"]').closest('.form-sidebar-item').hide();
            $('.assignments-section').hide();
            $('.sidebar-section.assignments').hide();
            
            // Hide any "Assign To" or "Assigned To" field in the form
            $('[data-fieldname="assign_to"]').hide();
            $('.frappe-control[data-fieldname="assign_to"]').hide();
            
            // Hide by label text "Assigned To" (catches any field with this label)
            $('.form-group').each(function() {
                var label = $(this).find('.control-label').text().trim();
                if (label === 'Assigned To' || label === 'Assign To') {
                    $(this).hide();
                }
            });
        }, 100);
        
        // If there's a standard assign_to field, hide it
        if (frm.fields_dict.assign_to) {
            frm.set_df_property('assign_to', 'hidden', 1);
        }
        
        // Hide any field with "assigned" in the fieldname, INCLUDING custom_assign_to
        Object.keys(frm.fields_dict).forEach(function(fieldname) {
            if (fieldname.toLowerCase().includes('assign')) {
                frm.set_df_property(fieldname, 'hidden', 1);
            }
        });
    },
    
    before_save(frm) {
        // Auto-assign to current user if not assigned
        if (frm.is_new() && !frm.doc.custom_assign_to) {
            frm.set_value('custom_assign_to', frappe.session.user);
        }
    }
});