// Name: Dispatch Case-Packing Problem Alerts
// DocType: Dispatch Case
// Enabled: 1
// ---

frappe.ui.form.on("Dispatch Case", {
    refresh(frm) {
        if (frm.doc.custom_packing_problem_status === "Problem Open") {
            frm.dashboard.add_comment(__("Packing problem is open: {0}", [frm.doc.custom_packing_problem_summary || "See item rows"]), "red", true);
        }
        if (!frm.is_new() && frm.doc.custom_packing_problem_status === "Problem Open") {
            frm.add_custom_button(__("Mark Packing Problem Reviewed"), function() {
                frm.set_value("custom_packing_problem_status", "Problem Reviewed");
                frm.save();
            }, __("Packing"));
        }
    }
});