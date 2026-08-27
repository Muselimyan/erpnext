// Name: Task-Delivery UI Fix
// DocType: Task
// Enabled: 1
// ---

frappe.ui.form.on("Task", {
    refresh(frm) {
        task_delivery_ui_fix_apply(frm);
        setTimeout(function() { task_delivery_ui_fix_apply(frm); }, 300);
        setTimeout(function() { task_delivery_ui_fix_apply(frm); }, 900);
    }
});

function task_delivery_ui_fix_apply(frm) {
    if (!frm || !frm.doc) return;
    var is_delivery = String(frm.doc.task_kind || "").trim() === "Delivery";
    document.body.classList.toggle("task-delivery-ui-active", is_delivery);
    if (!is_delivery) return;
    if (frm.fields_dict.custom_next_task_assign_to) {
        frm.set_df_property("custom_next_task_assign_to", "hidden", 0);
        frm.toggle_display("custom_next_task_assign_to", true);
    }
    if (!document.getElementById("task-delivery-ui-fix-css")) {
        var style = document.createElement("style");
        style.id = "task-delivery-ui-fix-css";
        style.textContent = [
            "@media(max-width:768px){",
            "body.task-delivery-ui-active .page-actions{flex-wrap:wrap!important;justify-content:flex-end!important;max-width:100%!important;overflow:visible!important;row-gap:4px!important}",
            "body.task-delivery-ui-active .page-actions .btn{max-width:46vw!important;white-space:normal!important;line-height:1.15!important;padding:4px 6px!important;font-size:11px!important}",
            "body.task-delivery-ui-active .page-head-content{flex-wrap:wrap!important;overflow:visible!important}",
            "body.task-delivery-ui-active .title-area{min-width:0!important;max-width:100%!important}",
            "}"
        ].join("");
        document.head.appendChild(style);
    }
}