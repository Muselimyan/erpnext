// Name: Task-Accept Start
// DocType: Task
// Enabled: 1
// ---
// After redesign: button creation (Accept, Save, Complete, mobile compact actions,
// "Accepted" gray bar, mobile Back circle, mobile Refresh) moved to Task-Action Buttons.js.
// This script retains: Account Details cleanup, assignment UI, field visibility,
// sidebar hiding, mobile CSS, menu cleanup, page title overflow fix,
// and mobile custom-actions hiding CSS.


function account_details_entry_ui_cleanup(frm) {
    if (frm.doc.task_kind !== "Account Details: Entry") return;

    var hideFields = [
        "custom_task_scan_barcode",
        "custom_task_scan_qty",
        "custom_task_choose_product",
        "custom_task_product_qty",
        "custom_task_add_batch_no",
        "custom_task_add_unit_price"
    ];

    hideFields.forEach(function(fieldname) {
        if (frm.fields_dict[fieldname]) {
            frm.toggle_display(fieldname, false);
            frm.set_df_property(fieldname, "hidden", 1);
        }
        $(frm.wrapper).find('[data-fieldname="' + fieldname + '"]').closest('.frappe-control').hide();
    });

    ["status", "priority"].forEach(function(fieldname) {
        if (frm.fields_dict[fieldname]) frm.toggle_display(fieldname, true);
    });

    if (frm.fields_dict.custom_account_photos) {
        frm.toggle_display("custom_account_photos", true);
    }

    setTimeout(function() {
        [
            "Barcode Scanning (Optional)",
            "Scan Product Barcode",
            "Scan Qty",
            "Choose Product",
            "Product Qty",
            "Batch / LOT",
            "Unit Price",
            "Warehouse Pickup Photo",
            "Warehouse Drop-off Photo"
        ].forEach(function(label) {
            $(frm.wrapper).find('.section-head').filter(function() { return $(this).text().trim() === label; }).closest('.form-section').hide();
            $(frm.wrapper).find('.control-label, label').filter(function() { return $(this).text().trim() === label; }).closest('.frappe-control').hide();
        });
    }, 300);

    $(frm.wrapper).find("#account-details-add-photos-btn").remove();
}

frappe.ui.form.on("Task", {
    custom_assigned_to(frm) {
    },
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
        
        // Unified assignment UI
        frm.set_df_property("custom_assigned_to", "label", "Assign To");
        frm.set_df_property("custom_next_task_assign_to", "label", "Next Task: Assign To");
        
        // Show next-task assignment for dispatch workflow tasks
        const dispatchKinds = ["Order entry", "Pack / prepare items", "Delivery", "Return Call", "Pickup Returns", "Returns processing / verification", "Returns restocking", "Invoice preparation / create invoice", "Discount Approval"];
        if (dispatchKinds.includes(frm.doc.task_kind) || frm.doc.task_kind === "Account Details: Entry") {
            frm.set_df_property("custom_next_task_assign_to", "hidden", 0);
        } else {
            frm.set_df_property("custom_next_task_assign_to", "hidden", 1);
        }
        account_details_entry_ui_cleanup(frm);
        if (frm.doc.task_kind === "Account Details: Entry" && frm.fields_dict.custom_next_task_assign_to) { frm.set_df_property("custom_next_task_assign_to", "hidden", 0); frm.toggle_display("custom_next_task_assign_to", true); }
        account_details_entry_keep_next_assign_empty(frm);
        // Hide sidebar items: Assign, Tags, Share, Like
        try {
            $(frm.wrapper).find('.like-action').hide();
            $(frm.wrapper).find('.form-assignments').hide();
            $(frm.wrapper).find('.form-tags').hide();
            $(frm.wrapper).find('.form-shared').hide();
        } catch(e) {}
        // Hide internal fields for clean UI
        frm.toggle_display("custom_accepted_by", false);
        frm.set_df_property("subject", "reqd", 0);
        if (frm.fields_dict.subject && frm.fields_dict.subject.df) {
            frm.fields_dict.subject.df.reqd = 0;
        }
        if (frm.doc.task_kind === "Order entry") {
            frm.toggle_display("subject", false);
            if (!frm.doc.subject) {
                frm.set_value("subject", frm.doc.name || "Order entry");
            }
        }
        // Hide Activity/Timesheet dashboard for all tasks
        frm.dashboard.hide();
        // Mobile: hide clutter fields for clean mobile UI
        if (window.innerWidth <= 768) {
            setTimeout(function() {
                var hideFields = ["custom_accepted_at","custom_task_add_batch_no","custom_task_add_unit_price"];
                hideFields.forEach(function(fn) {
                    $(frm.wrapper).find("[data-fieldname=\"" + fn + "\"]").closest(".frappe-control").hide();
                });
                $(frm.wrapper).find(".form-section .help-box").hide();
                // Hide Timeline section on mobile
                $(frm.wrapper).find(".form-footer .timeline-group, .form-footer .timeline-actions").hide();
                $(frm.wrapper).find(".section-head:contains('Timeline')").closest(".form-section").hide();
            }, 200);
        }
        // Default task_kind to Order entry on full form for new tasks
        if (frm.is_new() && frm.doc.task_kind === "Order accepting") {
            frm.set_value("task_kind", "Order entry");
        }
    }
});

function account_details_entry_keep_next_assign_empty(frm) {
    if (!frm || !frm.doc) return;
    if (String(frm.doc.task_kind || "").trim() !== "Account Details: Entry") return;
    var nextAssign = String(frm.doc.custom_next_task_assign_to || "").trim();
    var currentAssign = String(frm.doc.custom_assigned_to || "").trim();
    if (nextAssign && (!currentAssign || nextAssign === currentAssign)) {
        frm.set_value("custom_next_task_assign_to", "");
    }
}

// Mobile CSS: hide custom-actions and actions-btn-group in header on Task forms.
// This prevents Product Work Area dropdown buttons and other custom buttons from
// appearing in the cramped mobile header. The sub-header bar in Task-Action Buttons
// provides mobile-friendly access to these controls instead.
// All other header layout rules (title truncation, page-actions sizing) removed —
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
