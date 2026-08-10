#!/usr/bin/env bash
set -euo pipefail

docker exec -i frappe-backend-1 bench --site 161.97.83.156 console <<'PY'
import frappe
name = "Task-Other UI Cleanup"
doc = frappe.get_doc("Client Script", name)
script = doc.script or ""
start = script.find("function task_other_force_status_priority_visible(frm) {")
end = script.find("function task_other_render_photos", start)
if start < 0 or end < 0:
    raise Exception("Could not locate status/priority layout function boundaries")
old = script[start:end]
new = '''function task_other_force_status_priority_visible(frm) {
    task_restore_status_priority_complete_all(frm);
    var wrapper = $(frm.wrapper);
    var sectionControl = wrapper.find('[data-fieldname="custom_barcode_section"]').closest('.frappe-control');
    var statusControl = wrapper.find('[data-fieldname="status"]').closest('.frappe-control');
    var priorityControl = wrapper.find('[data-fieldname="priority"]').closest('.frappe-control');
    var statusSection = sectionControl.length ? sectionControl.closest('.form-section') : statusControl.closest('.form-section');
    var sectionHead = statusSection.find('.section-head').first();
    var leftColumn = statusSection.find('.form-column').first();
    sectionHead.text('Task Status & Priority');
    statusSection.show();
    if (leftColumn.length && statusControl.length) {
        var completeBtn = statusControl.find('#complete-task-btn').detach();
        statusControl.attr('data-other-status-left', 'otherStatusLeft').appendTo(leftColumn);
        if (completeBtn.length && !statusControl.find('#complete-task-btn').length) statusControl.append(completeBtn);
        if (priorityControl.length) priorityControl.appendTo(leftColumn);
        leftColumn.css({'float':'none','width':'100%','max-width':'640px','margin-left':'0','display':'block'});
        statusSection.find('.form-column').each(function(index) {
            if (index > 0) $(this).hide();
        });
    }
    statusControl.show();
    priorityControl.show();
    statusControl.find('#task-save-btn, #complete-task-btn').show();
}

'''
if old == new:
    print("already patched")
else:
    doc.script = script[:start] + new + script[end:]
    doc.save(ignore_permissions=True)
    frappe.db.commit()
    print("patched")
script = frappe.db.get_value("Client Script", name, "script") or ""
print("has_task_status_priority_label=", "sectionHead.text('Task Status & Priority')" in script)
print("has_left_column_width=", "max-width':'640px" in script)
print("has_hide_extra_columns=", "if (index > 0) $(this).hide();" in script)
PY

docker exec frappe-backend-1 bench --site 161.97.83.156 clear-cache
