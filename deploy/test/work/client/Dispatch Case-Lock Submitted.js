// Name: Dispatch Case-Lock Submitted
// DocType: Dispatch Case
// Enabled: 0
// ---
// DISABLED (v4 Phase 2): Conflicts with allow_on_submit model.
// Frappe natively handles submitted-doc behavior — allow_on_submit
// fields are editable, others are locked. The server script
// Dispatch-Case-before-save-lock-submitted.py is the authoritative
// lock for non-Directors.

frappe.ui.form.on('Dispatch Case', { refresh: function(frm) { if (frm.doc.docstatus !== 1) return; var roles = frappe.user_roles || []; var is_privileged = roles.indexOf('Ops - Directors') !== -1 || roles.indexOf('System Manager') !== -1 || roles.indexOf('Administrator') !== -1; if (!is_privileged) { frm.disable_save(); frm.set_read_only(); } } });