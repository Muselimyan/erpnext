// Name: Task-Auto Reload
// DocType: Task
// Enabled: 1
// ---

// Auto-reload Task form to prevent stale data
// 5-second cooldown prevents loops and avoids disrupting user after save
frappe.ui.form.on('Task', {
    refresh: function(frm) {
        if (frm.is_new()) return;
        if (frm.is_dirty()) return;
        var now = Date.now();
        var last = frm.__last_auto_reload || 0;
        // Only auto-reload if more than 5 seconds since last reload/save
        if (now - last > 5000) {
            frm.__last_auto_reload = now;
            frappe.call({
                method: 'frappe.client.get_value',
                args: { doctype: 'Task', filters: { name: frm.doc.name }, fieldname: 'modified' },
                async: true,
                callback: function(r) {
                    if (r && r.message && r.message.modified !== frm.doc.modified) {
                        console.log('[TaskAuto] reloading', {task: frm.doc.name, server_modified: r.message.modified, local_modified: frm.doc.modified});
                        frm.reload_doc();
                    }
                }
            });
        }
    },
    after_save: function(frm) {
        // Reset cooldown after save so we don't reload right after saving
        frm.__last_auto_reload = Date.now();
    }
});