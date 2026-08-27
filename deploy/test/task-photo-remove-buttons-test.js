frappe.ui.form.on("Task", {
    refresh(frm) {
        task_photo_remove_buttons_refresh(frm);
        setTimeout(function() { task_photo_remove_buttons_refresh(frm); }, 500);
        setTimeout(function() { task_photo_remove_buttons_refresh(frm); }, 1500);
    }
});

function task_photo_remove_buttons_refresh(frm) {
    if (!frm || !frm.doc || frm.is_new()) return;
    var fieldname = null;
    if (frm.doc.task_kind === "Pack / prepare items") fieldname = "warehouse_pickup_photo";
    if (frm.doc.task_kind === "Pickup Returns") fieldname = "warehouse_dropoff_photo";
    if (!fieldname) return;
    var ctrl = frm.fields_dict[fieldname];
    if (!ctrl || !ctrl.$wrapper) return;
    ctrl.$wrapper.find(".task-photo-remove-section").remove();
    frappe.call({
        method: "frappe.client.get_list",
        args: {
            doctype: "File",
            filters: {
                attached_to_doctype: "Task",
                attached_to_name: frm.doc.name
            },
            fields: ["name", "file_name", "file_url", "attached_to_field", "is_private"],
            limit_page_length: 50,
            order_by: "creation desc"
        },
        callback: function(r) {
            var files = (r && r.message) || [];
            files = files.filter(function(file) {
                if (file.attached_to_field && file.attached_to_field !== fieldname) return false;
                var url = String(file.file_url || "").toLowerCase();
                var name = String(file.file_name || "").toLowerCase();
                return /\.(png|jpg|jpeg|gif|webp|bmp|heic|heif|tif|tiff|svg)(\?|$)/.test(url) || /\.(png|jpg|jpeg|gif|webp|bmp|heic|heif|tif|tiff|svg)$/.test(name);
            });
            if (!files.length) return;
            var section = $('<div class="task-photo-remove-section" style="margin-top:10px;padding:10px;border:1px solid #ffd6d6;background:#fffafa;border-radius:6px;"></div>');
            section.append($('<div style="font-size:12px;font-weight:600;margin-bottom:8px;color:#b42318;"></div>').text(__('Remove wrong attached photo')));
            files.forEach(function(file) {
                var row = $('<div style="display:flex;align-items:center;justify-content:space-between;gap:8px;margin-top:6px;padding:6px 0;border-top:1px solid #f3dada;"></div>');
                var label = $('<div style="font-size:12px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;"></div>').text(file.file_name || file.name);
                var btn = $('<button class="btn btn-xs btn-danger" type="button" style="white-space:nowrap;">Remove</button>');
                btn.on("click", function() {
                    frappe.confirm(__('Remove this attached photo?'), function() {
                        btn.prop("disabled", true).text(__('Removing...'));
                        frappe.call({
                            method: "frappe.client.delete",
                            args: { doctype: "File", name: file.name },
                            callback: function() {
                                if (frm.doc[fieldname] === file.file_url) {
                                    frm.set_value(fieldname, "");
                                }
                                frappe.show_alert({ message: __('Photo removed'), indicator: 'green' });
                                frm.reload_doc();
                            },
                            error: function() {
                                btn.prop("disabled", false).text(__('Remove'));
                            }
                        });
                    });
                });
                row.append(label).append(btn);
                section.append(row);
            });
            ctrl.$wrapper.append(section);
        }
    });
}
