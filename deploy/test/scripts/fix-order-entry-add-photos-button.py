import frappe

name = "Task-Accept Start"
doc = frappe.get_doc("Client Script", name)
script = doc.script or ""
needle = "function task_mobile_order_entry_photos"
start = script.find(needle)
if start < 0:
    raise Exception("task_mobile_order_entry_photos not found")

new_func = r'''window.task_order_entry_add_photos_click = function(e) {
    if (e) {
        e.preventDefault();
        e.stopPropagation();
    }
    var frm = cur_frm;
    if (!frm || !frm.doc || String(frm.doc.task_kind || "").trim() !== "Order entry") {
        frappe.msgprint(__("Open an Order entry task before adding photos."));
        return false;
    }
    var openUploader = function() {
        if (!frm.doc.name || frm.doc.name.indexOf("new-") === 0) {
            frappe.msgprint(__("Save the Order entry task before adding photos."));
            return;
        }
        if (!frappe.ui || !frappe.ui.FileUploader) {
            frappe.msgprint(__("File uploader is not ready. Please refresh and try again."));
            return;
        }
        frappe.show_alert({ message: __("Opening photo uploader..."), indicator: "blue" });
        frappe.call({
            method: "frappe.client.get_count",
            args: { doctype: "File", filters: { attached_to_doctype: "Task", attached_to_name: frm.doc.name } },
            callback: function(r) {
                var existing = r.message || 0;
                if (existing >= 5) {
                    frappe.msgprint(__("Maximum 5 photos/files can be attached."));
                    return;
                }
                new frappe.ui.FileUploader({
                    doctype: "Task",
                    docname: frm.doc.name,
                    folder: "Home/Attachments",
                    allow_multiple: true,
                    restrictions: { allowed_file_types: ["image/*"], max_number_of_files: 5 - existing },
                    on_success: function() { frm.reload_doc(); }
                });
            },
            error: function() {
                frappe.msgprint(__("Could not check existing photos. Please refresh and try again."));
            }
        });
    };
    if (frm.is_dirty()) {
        frm.save().then(openUploader).catch(function() {
            frappe.msgprint(__("Please fix the save error before adding photos."));
        });
    } else {
        openUploader();
    }
    return false;
};

function task_mobile_order_entry_photos(frm) {
    if (!frm || !frm.doc) return;
    if (String(frm.doc.task_kind || "").trim() !== "Order entry") return;
    ["warehouse_pickup_photo", "warehouse_dropoff_photo", "custom_warehouse_pickup_photo", "custom_warehouse_drop_off_photo", "custom_warehouse_dropoff_photo"].forEach(function(fieldname) {
        if (frm.fields_dict[fieldname]) frm.toggle_display(fieldname, false);
        $(frm.wrapper).find('[data-fieldname="' + fieldname + '"]').closest('.frappe-control').hide();
    });
    ["Warehouse Pickup Photo", "Warehouse Drop-off Photo"].forEach(function(label) {
        $(frm.wrapper).find('.control-label, label').filter(function() { return $.trim($(this).text()) === label; }).closest('.frappe-control').hide();
    });
    $(frm.wrapper).find('[id="task-order-entry-add-photos-btn"], [id="account-details-add-photos-btn"]').remove();
    $(frm.wrapper).find('button').filter(function() { return $.trim($(this).text()) === "+ Add Photos"; }).remove();
    var anchor = frm.fields_dict.customer || frm.fields_dict.custom_next_task_assign_to || frm.fields_dict.status || frm.fields_dict.subject;
    if (!anchor || !anchor.$wrapper) return;
    var btn = $('<button id="task-order-entry-add-photos-btn" class="btn btn-sm btn-primary" type="button" onclick="return window.task_order_entry_add_photos_click(event)" style="font-size:12px;padding:5px 14px;background:#000;border-color:#000;color:#fff;border-radius:5px;margin-top:8px;margin-bottom:12px;display:block;">+ Add Photos</button>');
    btn.off("click.order_entry_photos").on("click.order_entry_photos", window.task_order_entry_add_photos_click);
    $(document).off("click.order_entry_photos", "#task-order-entry-add-photos-btn").on("click.order_entry_photos", "#task-order-entry-add-photos-btn", window.task_order_entry_add_photos_click);
    function placeOrderEntryPhotosButton() {
        $(frm.wrapper).find('button').filter(function() { return $.trim($(this).text()) === "+ Add Photos"; }).not(btn).remove();
        var target = $(frm.wrapper).find('.frappe-control[data-fieldname="customer"]:visible').first();
        if (!target.length) target = $(frm.wrapper).find('.frappe-control[data-fieldname="custom_next_task_assign_to"]:visible').first();
        if (!target.length) target = $(frm.wrapper).find('.frappe-control[data-fieldname="status"]:visible').first();
        if (target.length) btn.detach().insertAfter(target);
        else anchor.$wrapper.after(btn);
    }
    placeOrderEntryPhotosButton();
    setTimeout(placeOrderEntryPhotosButton, 300);
    setTimeout(placeOrderEntryPhotosButton, 1000);
}
'''

updated = script[:start] + new_func
frappe.db.sql(
    "update `tabClient Script` set script=%s, modified=now(), modified_by=%s where name=%s",
    (updated, frappe.session.user, name),
)
frappe.db.commit()
frappe.clear_cache(doctype="Client Script")
print("Updated Task-Accept Start Order entry Add Photos function on test")
