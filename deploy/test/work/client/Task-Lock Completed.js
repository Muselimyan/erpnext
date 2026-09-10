// Name: Task-Lock Completed
// DocType: Task
// Enabled: 0
// ---
// DISABLED: Absorbed into Task-Field-Editability.js (TFE) — 2026-09-09.

frappe.ui.form.on('Task', { refresh: function(frm) { frm.set_intro(''); if (frm.doc.status === 'Completed') { frm.disable_save(); frm.set_read_only(); frm.set_intro('This task is completed and cannot be modified.', 'green'); } } });