// Name: Task-Dispatch Packing Usability
// DocType: Task
// Enabled: 1
// ---

frappe.ui.form.on("Task", {
    refresh(frm) {
        if (frm.doc.task_kind === "Account details") return;
        frm.dashboard.clear_comment();
        if (frm.doc.dispatch_case) {
            frm.dashboard.add_comment(
                __("This task uses item rows from <b>Dispatch Case / Packing Items</b>. Open it to view quantities, batch/LOT, expiry, scanned and missing items."),
                "blue",
                true
            );
        }
        if (!frm.is_new() && ["Open", "Working"].includes(frm.doc.status) && frm.doc.custom_accepted_by !== frappe.session.user) {
            frm.add_custom_button(__("Accept / Start Task"), function() {
                frappe.call({ method: "dispatch_task_accept", args: { task_name: frm.doc.name }, freeze: true, callback: function() { frm.reload_doc(); } });
            });
            frm.change_custom_button_type(__("Accept / Start Task"), null, "primary");
        }
    }
});

frappe.listview_settings["Task"] = frappe.listview_settings["Task"] || {};
frappe.listview_settings["Task"].onload = function(listview) {
    listview.page.add_inner_button(__("My Team Queue"), function() {
        listview.filter_area.clear();
        listview.filter_area.add([["Task", "custom_is_team_queue_task", "=", 1]]);
        listview.filter_area.add([["Task", "custom_team_queue_status", "=", "Open For Team"]]);
        listview.refresh();
    });
};