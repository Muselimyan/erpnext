// Name: Task-Accept Start
// DocType: Task
// Enabled: 1
// ---
// TFV Phase 2: all field visibility logic removed.
// Task-Field-Visibility.js is the single source of truth for visibility.
// This script retains: mobile CSS, sidebar hiding, subject behavior,
// dashboard hide, Order entry kind default, mobile custom-actions CSS.

frappe.ui.form.on("Task", {
    status(frm) {
        if (frm.doc.status === "Completed" && !frm.doc.completed_on) {
            frm.set_value("completed_on", frappe.datetime.get_today());
        }
    },
    refresh(frm) {
        // Mobile: inject CSS to hide custom-actions (still needed for Product Work Area dropdown etc.)
        task_mobile_hide_desktop_custom_actions();
        // Mobile: inject global CSS for menu cleanup (once, on any page)
        if (window.innerWidth <= 768 && !document.getElementById("mobile-global-css")) {
            var css = document.createElement("style");
            css.id = "mobile-global-css";
            css.textContent = [
                "@media(max-width:768px){",
                ".menu-btn-group .dropdown-menu{min-width:92vw!important;white-space:normal!important}",
                "}"
            ].join("");
            document.head.appendChild(css);
            // Hide "Menu" text label
            document.querySelectorAll(".menu-btn-group .dropdown-toggle").forEach(function(btn) {
                btn.childNodes.forEach(function(n) {
                    if (n.nodeType === 3 && n.textContent.trim() === "Menu") n.textContent = "";
                });
                btn.querySelectorAll("span").forEach(function(sp) {
                    if (sp.textContent.trim() === "Menu") sp.style.display = "none";
                });
            });
        }
        if (window.innerWidth <= 768 && !window._mobileMenuSetup) {
            window._mobileMenuSetup = true;
            $(document).on("shown.bs.dropdown", function(e) {
                var dd = $(e.target).closest(".menu-btn-group, .dropdown").find(".dropdown-menu");
                if (!dd.length) dd = $(".dropdown-menu:visible");
                if (!dd.length) return;
                var hide = ["Toggle Sidebar","Email","Reload","Delete","Duplicate","New Task","Jump to field","Show Links","Copy to Clipboard","Remind Me","Undo","Redo","Customize","Edit DocType"];
                dd.find("a, button").each(function() {
                    var el = $(this);
                    var t = $.trim(el.clone().children("span, kbd, .text-muted").remove().end().text());
                    if (!t) t = $.trim(el.text());
                    for (var i = 0; i < hide.length; i++) {
                        if (t.indexOf(hide[i]) === 0) { el.hide(); el.parent("li").hide(); break; }
                    }
                });
                dd.find(".dropdown-divider, hr").hide();
                dd.css({"max-height":"70vh","overflow-y":"auto"});
                dd.find("a:visible, button:visible").css({"padding":"12px 18px","font-size":"15px","line-height":"1.5","white-space":"normal","word-wrap":"break-word","border-bottom":"1px solid #eee","margin":"0"});
            });
        }
        
        // Hide sidebar items: Assign, Tags, Share, Like
        try {
            $(frm.wrapper).find('.like-action').hide();
            $(frm.wrapper).find('.form-assignments').hide();
            $(frm.wrapper).find('.form-tags').hide();
            $(frm.wrapper).find('.form-shared').hide();
        } catch(e) {}
        // Subject: not required (auto-generated or user-set)
        frm.set_df_property("subject", "reqd", 0);
        if (frm.fields_dict.subject && frm.fields_dict.subject.df) {
            frm.fields_dict.subject.df.reqd = 0;
        }
        // Order entry: hide subject and auto-set (behavioral -- subject is auto-generated)
        if (frm.doc.task_kind === "Order entry") {
            frm.toggle_display("subject", false);
            if (!frm.doc.subject) {
                frm.set_value("subject", frm.doc.name || "Order entry");
            }
        }
        // Hide Activity/Timesheet dashboard for all tasks
        frm.dashboard.hide();
        // Default task_kind to Order entry on full form for new tasks
        if (frm.is_new() && frm.doc.task_kind === "Order accepting") {
            frm.set_value("task_kind", "Order entry");
        }
    }
});

// Mobile CSS: hide custom-actions and actions-btn-group in header on Task forms.
// This prevents Product Work Area dropdown buttons and other custom buttons from
// appearing in the cramped mobile header. The sub-header bar in Task-Action Buttons
// provides mobile-friendly access to these controls instead.
// All other header layout rules (title truncation, page-actions sizing) removed --
// Frappe's default responsive layout handles them correctly now that we have
// fewer buttons in the header.
function task_mobile_hide_desktop_custom_actions() {
    if (document.getElementById("task-mobile-hide-desktop-custom-actions")) return;
    var style = document.createElement("style");
    style.id = "task-mobile-hide-desktop-custom-actions";
    style.textContent = "@media (max-width: 768px) { " +
        "body[data-route^='Form/Task'] .page-head .custom-actions, body[data-route^='Form/Task'] .page-head .actions-btn-group { display: none !important; } " +
        "}";
    document.head.appendChild(style);
}
