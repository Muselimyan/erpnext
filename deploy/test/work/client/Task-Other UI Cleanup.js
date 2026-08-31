// Name: Task-Other UI Cleanup
// DocType: Task
// Enabled: 1
// ---
// After redesign: inline Complete button, inline Save button show, and duplicate
// Accept button removed — all handled by Task-Action Buttons.js.
// This script retains: field visibility for status/priority, "Other" task
// UI cleanup (subject, field hiding, section relabelling, layout).

frappe.ui.form.on("Task", {
    refresh(frm) { task_restore_status_priority_visible(frm); task_other_ui_cleanup(frm); setTimeout(function(){ task_restore_status_priority_visible(frm); task_other_ui_cleanup(frm); }, 200); setTimeout(function(){ task_restore_status_priority_visible(frm); task_other_ui_cleanup(frm); }, 800); setTimeout(function(){ task_restore_status_priority_visible(frm); task_other_ui_cleanup(frm); }, 1600); setTimeout(function(){ task_restore_status_priority_visible(frm); task_other_ui_cleanup(frm); }, 2600); },
    task_kind(frm) { task_other_ui_cleanup(frm); }
});

// Ensure status, priority, and barcode section fields remain visible.
// No button creation — buttons are owned by Task-Action Buttons.js.
function task_restore_status_priority_visible(frm) {
    if (!frm || frm.doctype !== "Task") return;
    ["status", "priority", "custom_barcode_section"].forEach(function(fieldname) { if (frm.fields_dict[fieldname]) frm.toggle_display(fieldname, true); });
    var statusField = frm.fields_dict.status;
    if (!statusField || !statusField.$wrapper) return;
    var wrapper = $(frm.wrapper);
    var statusControl = wrapper.find('[data-fieldname="status"]').closest('.frappe-control');
    var priorityControl = wrapper.find('[data-fieldname="priority"]').closest('.frappe-control');
    statusControl.closest('.form-section').show(); statusControl.closest('.form-column').show(); priorityControl.closest('.form-section').show(); priorityControl.closest('.form-column').show();
    statusControl.show(); priorityControl.show();
}

function task_other_ui_cleanup(frm) {
    if (!frm || frm.doctype !== "Task") return;
    var taskKind = String(frm.doc.task_kind || "").trim();
    var isOther = ["Other: Entry", "Other: Processing"].includes(taskKind);
    if (!isOther) return;
    frm.set_df_property("subject", "reqd", 0); frm.set_df_property("subject", "label", "Task Name"); frm.toggle_display("subject", true);
    if (frm.fields_dict.subject && frm.fields_dict.subject.df) frm.fields_dict.subject.df.reqd = 0;
    if (taskKind === "Other: Entry" && (!frm.doc.subject || frm.doc.subject === "New Task" || frm.doc.subject === "Other")) frm.set_value("subject", "Other: Entry");
    if (taskKind === "Other: Processing" && (!frm.doc.subject || frm.doc.subject === "New Task" || frm.doc.subject === "Other")) frm.set_value("subject", "Other: Processing");
    ["status", "priority", "custom_barcode_section"].forEach(function(fieldname) { if (frm.fields_dict[fieldname]) frm.toggle_display(fieldname, true); });
    if (frm.fields_dict.custom_next_task_assign_to) { frm.set_df_property("custom_next_task_assign_to", "label", "Next Task: Assign To"); frm.toggle_display("custom_next_task_assign_to", String(frm.doc.subject || "") !== "Other: Processing"); }
    ["other_items", "other_budget", "other_supplier", "custom_product_work_section", "custom_task_product_summary", "custom_product_lines", "custom_task_add_item_code", "custom_task_add_qty", "custom_task_add_batch_no", "custom_task_add_unit_price", "custom_task_scan_barcode", "custom_task_scan_qty", "custom_task_scan_result", "custom_product_work_column", "custom_task_product_warning"].forEach(function(fieldname) { if (frm.fields_dict[fieldname]) frm.toggle_display(fieldname, false); });
    setTimeout(function() {
        var wrapper = $(frm.wrapper);
        wrapper.find('[data-fieldname="custom_product_work_section"]').closest('.form-section').hide();
        wrapper.find('[data-fieldname="custom_task_scan_barcode"], [data-fieldname="custom_task_scan_qty"], [data-fieldname="custom_task_scan_result"], [data-fieldname="custom_product_work_column"], [data-fieldname="custom_task_product_warning"]').closest('.frappe-control').hide();
        wrapper.find('[data-fieldname="other_items"], [data-fieldname="other_budget"], [data-fieldname="other_supplier"], [data-fieldname="custom_product_lines"]').closest('.frappe-control').hide();
        wrapper.find('.control-label, label').filter(function() { return $.trim($(this).text()) === "Topic"; }).each(function() { var control = $(this).closest('.frappe-control'); if (!control.find('[data-fieldname="subject"]').length && control.attr('data-fieldname') !== 'subject') control.hide(); });
        wrapper.find('.section-head').filter(function() { return $.trim($(this).text()) === "Products / Dispatch Work"; }).closest('.form-section').hide();
        task_other_force_status_priority_visible(frm);
    }, 100);
}

function task_other_force_status_priority_visible(frm) {
    task_restore_status_priority_visible(frm);
    var wrapper = $(frm.wrapper);
    var sectionControl = wrapper.find('[data-fieldname="custom_barcode_section"]').closest('.frappe-control');
    var statusControl = wrapper.find('[data-fieldname="status"]').closest('.frappe-control');
    var priorityControl = wrapper.find('[data-fieldname="priority"]').closest('.frappe-control');
    var statusSection = sectionControl.closest('.form-section');
    var sectionHead = statusSection.find('.section-head').first();
    var leftColumn = statusSection.find('.form-column').first();
    sectionHead.text('Status and Priority');
    statusSection.find('#other-status-priority-left-host').remove();
    if (leftColumn.length && statusControl.length) {
        statusControl.appendTo(leftColumn);
        if (priorityControl.length) priorityControl.appendTo(leftColumn);
        leftColumn.css({'float':'none','width':'360px','max-width':'100%','margin-left':'0','display':'block'});
    }
    statusSection.show();
    statusControl.show();
    priorityControl.show();
}
