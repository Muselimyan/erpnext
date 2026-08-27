// Name: Task-Inspect Returns Next Assign Visible
// DocType: Task
// Enabled: 1
// ---

frappe.ui.form.on('Task', {
    refresh: function(frm) {
        task_inspect_returns_next_assign_visible(frm);
        setTimeout(function() { task_inspect_returns_next_assign_visible(frm); }, 300);
        setTimeout(function() { task_inspect_returns_next_assign_visible(frm); }, 1000);
    },
    task_kind: function(frm) {
        task_inspect_returns_next_assign_visible(frm);
    }
});

function task_inspect_returns_next_assign_visible(frm) {
    if (!frm || !frm.doc || frm.doc.task_kind !== 'Returns processing / verification') return;
    if (!frm.fields_dict || !frm.fields_dict.custom_next_task_assign_to) return;
    frm.set_df_property('custom_next_task_assign_to', 'label', 'Next Task: Assign To');
    frm.set_df_property('custom_next_task_assign_to', 'hidden', 0);
    frm.toggle_display('custom_next_task_assign_to', true);
    if (frm.fields_dict.custom_next_task_assign_to.$wrapper) {
        frm.fields_dict.custom_next_task_assign_to.$wrapper.show();
    }
}