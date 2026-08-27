#!/usr/bin/env bash
set -euo pipefail

docker exec -i frappe-backend-1 bench --site 161.97.83.156 console <<'PY'
import frappe
name = "Task-Account Details UI Cleanup"
doc = frappe.get_doc("Client Script", name)
script = doc.script or ""
old1 = '''    if (taskKind === "account details: processing" && frm.fields_dict.custom_next_task_assign_to) {
        frm.toggle_display("custom_next_task_assign_to", false);
    }
    if (frm.fields_dict.custom_next_task_assign_to) {
        frm.set_df_property("custom_next_task_assign_to", "label", "Next Task: Assign To");
        frm.toggle_display("custom_next_task_assign_to", true);
    }'''
new1 = '''    if (frm.fields_dict.custom_next_task_assign_to) {
        frm.set_df_property("custom_next_task_assign_to", "label", "Next Task: Assign To");
        frm.toggle_display("custom_next_task_assign_to", taskKind !== "account details: processing");
    }'''
old2 = '''            nextAssignControl.show();'''
new2 = '''            if (taskKind === "account details: processing") {
                nextAssignControl.hide();
            } else {
                nextAssignControl.show();
            }'''
if old1 not in script:
    raise Exception("Expected initial next task toggle block not found")
if old2 not in script:
    raise Exception("Expected delayed next task show line not found")
script = script.replace(old1, new1, 1).replace(old2, new2, 1)
doc.script = script
doc.save(ignore_permissions=True)
frappe.db.commit()
print("patched")
script = frappe.db.get_value("Client Script", name, "script") or ""
print("has_conflicting_processing_toggle=", old1 in script)
print("has_processing_hide_in_delayed_layout=", 'if (taskKind === "account details: processing") {\n                nextAssignControl.hide();' in script)
PY

docker exec frappe-backend-1 bench --site 161.97.83.156 clear-cache
