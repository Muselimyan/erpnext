// Name: Task-Other UI Cleanup
// DocType: Task
// Enabled: 1
// ---
// TFV Phase 3: all field visibility logic removed.
// Task-Field-Visibility.js is the single source of truth for visibility.
// This script retains only: subject defaulting for Other: Entry / Other: Processing tasks.
// Removed: task_restore_status_priority_visible, task_other_force_status_priority_visible,
// product/scan field hiding, section label renaming, DOM column rearrangement,
// status/priority/barcode force-show with setTimeout retries.

frappe.ui.form.on("Task", {
    refresh(frm) { task_other_ui_cleanup(frm); },
    task_kind(frm) { task_other_ui_cleanup(frm); }
});

function task_other_ui_cleanup(frm) {
    if (!frm || frm.doctype !== "Task") return;
    var taskKind = String(frm.doc.task_kind || "").trim();
    var isOther = ["Other: Entry", "Other: Processing"].includes(taskKind);
    if (!isOther) return;
    // Subject: not required, relabel to "Task Name", default value per kind
    frm.set_df_property("subject", "reqd", 0);
    frm.set_df_property("subject", "label", "Task Name");
    if (frm.fields_dict.subject && frm.fields_dict.subject.df) frm.fields_dict.subject.df.reqd = 0;
    if (taskKind === "Other: Entry" && (!frm.doc.subject || frm.doc.subject === "New Task" || frm.doc.subject === "Other")) frm.set_value("subject", "Other: Entry");
    if (taskKind === "Other: Processing" && (!frm.doc.subject || frm.doc.subject === "New Task" || frm.doc.subject === "Other")) frm.set_value("subject", "Other: Processing");
}
