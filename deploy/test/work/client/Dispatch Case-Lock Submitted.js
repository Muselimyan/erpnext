// Name: Dispatch Case-Lock Submitted
// DocType: Dispatch Case
// Enabled: 1
// ---

frappe.ui.form.on('Dispatch Case', { refresh: function(frm) { if (frm.doc.docstatus !== 1) return; var roles = frappe.user_roles || []; var is_privileged = roles.indexOf('Ops - Directors') !== -1 || roles.indexOf('System Manager') !== -1 || roles.indexOf('Administrator') !== -1; if (!is_privileged) { frm.disable_save(); frm.set_read_only(); } } });