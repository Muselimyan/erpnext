// Name: Dispatch Case-Item Code Toggle
// DocType: Dispatch Case
// Enabled: 0
// ---

frappe.listview_settings['Task'] = frappe.listview_settings['Task'] || {};

frappe.listview_settings['Task'].onload = function(listview) {
    // Add custom button to page toolbar
    listview.page.add_inner_button(__('Toggle My Custom Filter'), function() {
        applyToggleFilter(listview);
    });
};

function applyToggleFilter(listview) {
    const target_list = listview || cur_list;

    if (!target_list) {
        console.error("[TaskToggle] Listview instance not found.");
        return;
    }

    frappe.call({
        method: "your_app.api.get_filtered_tasks", // <-- Replace with actual Python path
        args: {},
        freeze: true,
        freeze_message: __("Filtering tasks..."),
        callback: function(r) {
            if (r.message && Array.isArray(r.message) && r.message.length > 0) {
                console.log("[TaskToggle] API returned", r.message.length, "tasks");

                // Route directly with the 'in' array filter
                frappe.set_route("List", "Task", "List", {
                    "name": ["in", r.message]
                });
            } else {
                frappe.msgprint(__('No tasks found matching the selected criteria.'));
            }
        }
    });
}