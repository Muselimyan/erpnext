// Name: Task-Header Long Subject Fix
// DocType: Task
// Enabled: 0
// ---
// DISABLED — Header unification (Option B). This script forced subject
// visible with !important CSS, overriding Task-Accept Start's deliberate
// hiding of subject for Order Entry. Each task kind now manages subject
// visibility correctly on its own. Subject input sizing (38px, 15px)
// relocated to Task-Action Buttons.js.

frappe.ui.form.on('Task', {
    refresh: function(frm) {
        task_subject_field_visibility_fix(frm);
        setTimeout(function() { task_subject_field_visibility_fix(frm); }, 250);
        setTimeout(function() { task_subject_field_visibility_fix(frm); }, 900);
    },
    subject: function(frm) {
        task_subject_field_visibility_fix(frm);
    }
});

function task_subject_field_visibility_fix(frm) {
    try {
        var oldStyle = document.getElementById('task-header-long-subject-fix');
        if (oldStyle) oldStyle.remove();

        if (!document.getElementById('task-subject-field-visibility-fix')) {
            var style = document.createElement('style');
            style.id = 'task-subject-field-visibility-fix';
            style.textContent = `
body[data-route^="Form/Task"] [data-fieldname="subject"],
body[data-route^="Form/Task"] [data-fieldname="subject"] .control-input-wrapper,
body[data-route^="Form/Task"] [data-fieldname="subject"] .control-input {
    display: block !important;
    visibility: visible !important;
}
body[data-route^="Form/Task"] .task-visible-subject-banner {
    display: none !important;
    visibility: hidden !important;
}
`;
            document.head.appendChild(style);
        }

        if (frm && frm.fields_dict && frm.fields_dict.subject) {
            frm.toggle_display('subject', true);
            frm.set_df_property('subject', 'hidden', 0);
        }
        if (frm && frm.wrapper) {
            $(frm.wrapper).find('.task-visible-subject-banner').remove();
            $(frm.wrapper).find('[data-fieldname="subject"]').closest('.frappe-control').show().css({ display: 'block', visibility: 'visible' });
        }
    } catch (e) {}
}