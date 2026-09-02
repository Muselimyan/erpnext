// Name: Task-Action Buttons
// DocType: Task
// Enabled: 1
// ---
// Unified button script for Task forms.
// Owns: Accept, Create DC, Open DC, Complete (desktop header + mobile bottom floating).
// Mobile sub-header bar: Back, Refresh, Open DC, Products.
// Also owns: generic mobile CSS (tabs, grids, padding, subject sizing) and scroll-to-top.
// Replaces buttons previously in Task-Accept Start, Task-Create Dispatch Case Items,
// Task-Dispatch Packing Usability.
// Generic mobile CSS relocated from Task-Mobile Form Layout Fix (header unification).

// ── cleanup orphaned CSS/classes from disabled scripts ────────
function tab_cleanup_disabled_scripts() {
    // Remove CSS elements injected by now-disabled scripts.
    // These persist in the DOM across navigation even after the script is disabled.
    var orphans = [
        "task-mobile-form-layout-fix-style",   // Task-Mobile Form Layout Fix
        "task-delivery-ui-fix-css",            // Task-Delivery UI Fix
        "task-subject-field-visibility-fix",   // Task-Header Long Subject Fix
        "task-header-long-subject-fix"         // old dead CSS from Header Long Subject Fix
    ];
    orphans.forEach(function(id) {
        var el = document.getElementById(id);
        if (el) {
            el.remove();
            console.log("[TaskButtons] Removed orphaned style #" + id);
        }
    });
    // Remove orphaned body classes
    var bodyClasses = ["task-mobile-pack-clean", "task-delivery-ui-active"];
    bodyClasses.forEach(function(cls) {
        if (document.body.classList.contains(cls)) {
            document.body.classList.remove(cls);
            console.log("[TaskButtons] Removed orphaned body class: " + cls);
        }
    });
    // Remove orphaned DOM elements (summary card, old mobile back buttons on Task forms)
    $(".task-mobile-pack-summary").remove();
}

// ── generic mobile CSS (injected once) ────────────────────────
function tab_inject_mobile_css() {
    if (window.innerWidth > 768) return;
    if (document.getElementById("task-mobile-layout-css")) return;
    var style = document.createElement("style");
    style.id = "task-mobile-layout-css";
    style.textContent = "@media (max-width: 768px) {" +
        // Horizontal tab scrolling — prevents tab bar wrapping on narrow screens
        "body[data-route^='Form/Task'] .form-tabs-list," +
        "body[data-route^='Form/Task'] .form-tabs {" +
            "overflow-x: auto !important;" +
            "overflow-y: hidden !important;" +
            "flex-wrap: nowrap !important;" +
            "white-space: nowrap !important;" +
        "}" +
        // Bottom padding so floating action buttons don't cover form content
        "body[data-route^='Form/Task'] .form-page {" +
            "padding-bottom: 92px !important;" +
        "}" +
        // Subject input sizing for touch (does not affect visibility)
        "body[data-route^='Form/Task'] [data-fieldname='subject'] input," +
        "body[data-route^='Form/Task'] [data-fieldname='subject'] textarea {" +
            "min-height: 38px !important;" +
            "font-size: 15px !important;" +
        "}" +
        // Grid horizontal scrolling
        "body[data-route^='Form/Task'] .grid-body," +
        "body[data-route^='Form/Task'] .form-grid {" +
            "overflow-x: auto !important;" +
            "-webkit-overflow-scrolling: touch !important;" +
        "}" +
        // Minimum row width prevents column squishing
        "body[data-route^='Form/Task'] .grid-row," +
        "body[data-route^='Form/Task'] .grid-heading-row {" +
            "min-width: 330px !important;" +
        "}" +
        // Readable grid cells on mobile
        "body[data-route^='Form/Task'] .grid-static-col {" +
            "min-height: 54px !important;" +
            "padding: 8px 7px !important;" +
            "white-space: normal !important;" +
            "overflow-wrap: anywhere !important;" +
            "line-height: 1.25 !important;" +
        "}" +
        // Bigger checkboxes for touch targets
        "body[data-route^='Form/Task'] .grid-static-col input[type='checkbox']," +
        "body[data-route^='Form/Task'] .grid-static-col .checkbox input {" +
            "width: 22px !important;" +
            "height: 22px !important;" +
            "min-width: 22px !important;" +
            "min-height: 22px !important;" +
        "}" +
    "}";
    document.head.appendChild(style);
}

// ── scroll to top on new task (relocated from Task-Mobile Form Layout Fix) ──
function tab_mobile_scroll_to_top(frm) {
    if (!frm || !frm.doc || window.innerWidth > 768) return;
    if (frm._task_mobile_last_scroll_doc === frm.doc.name) return;
    frm._task_mobile_last_scroll_doc = frm.doc.name;
    window.scrollTo(0, 0);
    document.documentElement.scrollTop = 0;
    document.body.scrollTop = 0;
    $(".main-section, .layout-main-section, .layout-main-section-wrapper, .form-page").scrollTop(0);
}

// ── constants ──────────────────────────────────────────────────
var TAB_DISPATCH_KINDS = [
    "Pack / prepare items", "Dispatch picking / hand-off", "Delivery",
    "Pickup Returns", "Return drop-off at warehouse", "Returns processing / verification",
    "Returns restocking", "Invoice preparation / create invoice", "Debt Collection", "Discount Approval"
];
var TAB_OPERATIONAL_KINDS = [
    "Order entry", "Pack / prepare items", "Dispatch picking / hand-off", "Delivery", "Return Call",
    "Pickup Returns", "Return drop-off at warehouse", "Returns processing / verification",
    "Returns restocking", "Invoice preparation / create invoice", "Debt Collection", "Debt Closure Approval",
    "Discount Approval", "Purchase Approval", "Write-off Approval"
];
var TAB_PRODUCT_KINDS = [
    "Pack / prepare items", "Dispatch picking / hand-off", "Delivery", "Pickup Returns",
    "Return drop-off at warehouse", "Returns processing / verification", "Returns restocking",
    "Invoice preparation / create invoice", "Discount Approval"
];

// ── helpers ────────────────────────────────────────────────────
function tab_is_mobile() { return window.innerWidth <= 768; }

function tab_is_admin() {
    var roles = frappe.user_roles || [];
    return roles.indexOf("System Manager") !== -1 || roles.indexOf("Administrator") !== -1 || frappe.session.user === "Administrator";
}

function tab_is_accepted(frm) {
    return !!frm.doc.custom_accepted_by;
}

function tab_can_act(frm) {
    if (!tab_is_accepted(frm)) return false;
    return frm.doc.custom_accepted_by === frappe.session.user || tab_is_admin();
}

function tab_needs_dc(frm) {
    return frm.doc.task_kind === "Order entry" || TAB_DISPATCH_KINDS.indexOf(frm.doc.task_kind) !== -1;
}

function tab_is_product_task(frm) {
    return !!frm.doc.dispatch_case || TAB_PRODUCT_KINDS.indexOf(frm.doc.task_kind) !== -1;
}

function tab_do_accept(frm) {
    frappe.call({
        method: "dispatch_task_accept",
        args: { task_name: frm.doc.name },
        freeze: true,
        freeze_message: __("Accepting task..."),
        callback: function() { frm.reload_doc(); }
    });
}

function tab_do_create_dc(frm) {
    frappe.call({
        method: "task_create_dispatch_case",
        args: { task_name: frm.doc.name },
        freeze: true,
        freeze_message: __("Creating Dispatch Case..."),
        callback: function(r) {
            var msg = r.message || {};
            if (msg.dispatch_case) {
                frappe.show_alert({ message: __("Dispatch Case created"), indicator: "green" });
                frm.reload_doc();
            }
        }
    });
}

function tab_do_complete(frm, btn) {
    if (btn && btn.data && btn.data("busy")) return;
    var originalStatus = frm.doc.status;
    var originalCompletedOn = frm.doc.completed_on;
    if (btn) btn.data("busy", true).prop("disabled", true).text("Completing...");

    // Set completion fields on the local doc before sending
    frm.doc.status = "Completed";
    if (!frm.doc.completed_on) frm.doc.completed_on = frappe.datetime.get_today();
    frm.doc.__unsaved = 1;

    // Call savedocs directly via frappe.call — bypasses frm.save() which has
    // unreliable promise rejection and argument-signature issues.
    // frappe.call error callback fires reliably for all server errors.
    frappe.call({
        method: "frappe.desk.form.save.savedocs",
        args: { doc: frm.doc, action: "Save" },
        freeze: true,
        freeze_message: __("Completing..."),
        callback: function() {
            if (btn) btn.data("busy", false);
            frm.reload_doc();
        },
        error: function() {
            frm.doc.status = originalStatus;
            frm.doc.completed_on = originalCompletedOn || "";
            if (btn) btn.data("busy", false).prop("disabled", false).text("Complete");
        }
    });
}

// ── dashboard comments (absorbed from Task-Dispatch Packing Usability) ──
function tab_dashboard_comments(frm) {
    frm.dashboard.clear_comment();
    if (frm.doc.dispatch_case) {
        frm.dashboard.add_comment(
            __("This task uses item rows from <b>Dispatch Case / Packing Items</b>. Open it to view quantities, batch/LOT, expiry, scanned and missing items."),
            "blue", true
        );
    } else if (tab_needs_dc(frm) && !frm.is_new()) {
        frm.dashboard.add_comment(
            __("This task needs a <b>Dispatch Case</b> before item rows can be managed."),
            "orange", true
        );
    }
}

// ── mobile sub-header bar ──────────────────────────────────────
function tab_render_subheader(frm) {
    if (!tab_is_mobile()) return;
    $(frm.wrapper).find("#task-subheader").remove();

    var bar = $('<div id="task-subheader" style="display:flex;align-items:center;justify-content:space-between;padding:6px 12px;background:#f7f7f7;border-bottom:1px solid #d1d8dd;gap:6px;flex-wrap:nowrap;"></div>');

    // Left: Back + Refresh
    var left = $('<div style="display:flex;gap:6px;align-items:center;"></div>');
    var backBtn = $('<button class="btn btn-default btn-sm" style="font-size:16px;padding:4px 10px;">&#x2190;</button>');
    backBtn.on("click", function() {
        if (window.history.length > 1) history.back();
        else frappe.set_route("List", "Task");
    });
    var refreshBtn = $('<button class="btn btn-default btn-sm" style="font-size:14px;padding:4px 10px;">&#x21bb;</button>');
    refreshBtn.on("click", function() { frm.reload_doc(); });
    left.append(backBtn).append(refreshBtn);
    bar.append(left);

    // Right: contextual buttons
    var right = $('<div style="display:flex;gap:6px;align-items:center;"></div>');

    // Product controls (dropdown)
    if (!frm.is_new() && tab_is_product_task(frm) && tab_can_act(frm)) {
        var prodDrop = $('<div class="dropdown" style="display:inline-block;"></div>');
        var prodToggle = $('<button class="btn btn-default btn-sm dropdown-toggle" data-toggle="dropdown" style="font-size:12px;padding:4px 8px;">Products</button>');
        var prodMenu = $('<div class="dropdown-menu dropdown-menu-right" style="min-width:180px;"></div>');
        var items = [
            { label: __("Add Selected Product"), fn: function() { if (typeof task_product_work_area_add_product === "function") task_product_work_area_add_product(frm); } },
            { label: __("Refresh Products"), fn: function() { if (typeof task_product_work_area_refresh === "function") task_product_work_area_refresh(frm, true); } },
            { label: __("Scan Product Barcode"), fn: function() { if (typeof task_product_work_area_scan === "function") task_product_work_area_scan(frm); } }
        ];
        items.forEach(function(item) {
            var a = $('<a class="dropdown-item" href="#" style="padding:8px 14px;font-size:13px;"></a>').text(item.label);
            a.on("click", function(e) { e.preventDefault(); item.fn(); });
            prodMenu.append(a);
        });
        prodDrop.append(prodToggle).append(prodMenu);
        right.append(prodDrop);
    }

    // Open Dispatch Case
    if (frm.doc.dispatch_case) {
        var dcBtn = $('<button class="btn btn-default btn-sm" style="font-size:12px;padding:4px 8px;">Open DC</button>');
        dcBtn.on("click", function() { frappe.set_route("Form", "Dispatch Case", frm.doc.dispatch_case); });
        right.append(dcBtn);
    }

    bar.append(right);

    // Inject after page-head
    var pageHead = $(frm.page.wrapper).find(".page-head");
    if (pageHead.length) {
        pageHead.after(bar);
    } else {
        $(frm.wrapper).find(".form-layout").before(bar);
    }
}

// ── mobile bottom floating buttons ─────────────────────────────
function tab_render_bottom_actions(frm) {
    if (!tab_is_mobile()) return;
    $(frm.wrapper).find("#task-bottom-actions").remove();

    if (frm.is_new() || frm.doc.status === "Completed" || frm.doc.status === "Cancelled") return;

    var container = $('<div id="task-bottom-actions" style="position:fixed;bottom:20px;left:0;right:0;z-index:9999;display:flex;justify-content:center;align-items:center;gap:12px;padding:0 20px;pointer-events:none;"></div>');

    var isAccepted = tab_can_act(frm);
    var needsAccept = ["Open", "Working"].indexOf(frm.doc.status) !== -1 && frm.doc.custom_accepted_by !== frappe.session.user;
    var hasDC = !!frm.doc.dispatch_case;
    var needsDC = tab_needs_dc(frm) && !hasDC;

    if (needsAccept && !isAccepted) {
        // State A: Accept only
        var acceptBtn = $('<button style="pointer-events:auto;padding:14px 32px;font-size:17px;font-weight:bold;background:#1976d2;color:#fff;border:none;border-radius:12px;cursor:pointer;box-shadow:0 4px 12px rgba(0,0,0,0.25);min-width:200px;">Accept / Start Task</button>');
        acceptBtn.on("click", function() {
            if (frm.is_new() || frm.dirty()) {
                frm.save().then(function() {
                    if (frm.doc.name && frm.doc.name.indexOf("new-") !== 0) tab_do_accept(frm);
                    else { frappe.show_alert({message: __("Task saved. Please accept again."), indicator: "orange"}, 8); frm.reload_doc(); }
                });
            } else {
                tab_do_accept(frm);
            }
        });
        container.append(acceptBtn);
    } else if (isAccepted) {
        // State B or C: action buttons
        if (needsDC) {
            // Create DC — center
            var createDCBtn = $('<button style="pointer-events:auto;padding:14px 24px;font-size:15px;font-weight:bold;background:#1976d2;color:#fff;border:none;border-radius:12px;cursor:pointer;box-shadow:0 4px 12px rgba(0,0,0,0.25);">Create Dispatch Case</button>');
            createDCBtn.on("click", function() {
                if (!frm.doc.customer) { frappe.msgprint(__("Select Customer on this Task first.")); return; }
                if (frm.dirty()) { frm.save().then(function() { tab_do_create_dc(frm); }); }
                else tab_do_create_dc(frm);
            });
            container.append(createDCBtn);
        }

        // Complete — right
        var completeBtn = $('<button style="pointer-events:auto;padding:14px 24px;font-size:15px;font-weight:bold;background:#27ae60;color:#fff;border:none;border-radius:12px;cursor:pointer;box-shadow:0 4px 12px rgba(0,0,0,0.25);margin-left:auto;">Complete</button>');
        completeBtn.on("click", function() { tab_do_complete(frm, $(this)); });
        container.append(completeBtn);
    }

    if (container.children().length) {
        $(frm.wrapper).find(".form-layout").append(container);
    }
}

// ── desktop header buttons ─────────────────────────────────────
function tab_render_desktop_buttons(frm) {
    if (tab_is_mobile()) return;
    if (frm.is_new()) return;

    var isAccepted = tab_can_act(frm);
    var needsAccept = ["Open", "Working"].indexOf(frm.doc.status) !== -1 && frm.doc.custom_accepted_by !== frappe.session.user;
    var hasDC = !!frm.doc.dispatch_case;
    var needsDC = tab_needs_dc(frm) && !hasDC;
    var isCompleted = frm.doc.status === "Completed";
    var isCancelled = frm.doc.status === "Cancelled";

    // Open DC — always if DC exists
    if (hasDC) {
        frm.add_custom_button(__("Open Dispatch Case"), function() {
            frappe.set_route("Form", "Dispatch Case", frm.doc.dispatch_case);
        });
    }

    if (!isCompleted && !isCancelled) {
        // Complete Task
        if (isAccepted) {
            frm.add_custom_button(__("Complete Task"), function() {
                tab_do_complete(frm, null);
            });
        }

        // Create DC
        if (isAccepted && needsDC) {
            frm.add_custom_button(__("Create Dispatch Case"), function() {
                if (!frm.doc.customer) { frappe.msgprint(__("Select Customer on this Task first.")); return; }
                if (frm.dirty()) { frm.save().then(function() { tab_do_create_dc(frm); }); }
                else tab_do_create_dc(frm);
            });
            frm.change_custom_button_type(__("Create Dispatch Case"), null, "primary");
        }

        // Accept
        if (needsAccept && !isAccepted) {
            frm.add_custom_button(__("Accept / Start Task"), function() {
                if (frm.is_new() || frm.dirty()) {
                    frm.save().then(function() {
                        if (frm.doc.name && frm.doc.name.indexOf("new-") !== 0) tab_do_accept(frm);
                        else { frappe.show_alert({message: __("Task saved. Please accept again."), indicator: "orange"}, 8); frm.reload_doc(); }
                    });
                } else {
                    tab_do_accept(frm);
                }
            });
            frm.change_custom_button_type(__("Accept / Start Task"), null, "primary");
        }
    }
}

// ── debug logging ─────────────────────────────────────────────
function tab_debug_header(frm) {
    var isMobile = window.innerWidth <= 768;
    var pageHead = $(frm.page.wrapper).find(".page-head");
    var titleArea = pageHead.find(".title-area");
    var titleText = pageHead.find(".title-text");
    var customActions = pageHead.find(".custom-actions");
    var pageActions = pageHead.find(".page-actions");

    console.log("[TaskButtons] ─── Header Debug ───");
    console.log("[TaskButtons] Task:", frm.doc.name, "| Kind:", frm.doc.task_kind, "| Status:", frm.doc.status);
    console.log("[TaskButtons] Mobile:", isMobile, "| Accepted:", !!frm.doc.custom_accepted_by, "| DC:", frm.doc.dispatch_case || "none");
    console.log("[TaskButtons] .title-area visible:", titleArea.is(":visible"), "| display:", titleArea.css("display"));
    console.log("[TaskButtons] .title-text content:", (titleText.text() || "").substring(0, 60));
    console.log("[TaskButtons] .custom-actions visible:", customActions.is(":visible"), "| display:", customActions.css("display"));
    console.log("[TaskButtons] .page-actions display:", pageActions.css("display"), "| flex-wrap:", pageActions.css("flex-wrap"));

    // Check for orphaned styles that should have been cleaned up
    var orphanIds = ["task-delivery-ui-fix-css", "task-mobile-form-layout-fix-style", "task-subject-field-visibility-fix"];
    var foundOrphans = orphanIds.filter(function(id) { return !!document.getElementById(id); });
    if (foundOrphans.length) {
        console.warn("[TaskButtons] ORPHANED STYLES STILL PRESENT:", foundOrphans.join(", "));
    } else {
        console.log("[TaskButtons] No orphaned styles (clean)");
    }

    // Check body classes
    var bodyClasses = ["task-mobile-pack-clean", "task-delivery-ui-active"];
    var activeClasses = bodyClasses.filter(function(cls) { return document.body.classList.contains(cls); });
    if (activeClasses.length) {
        console.warn("[TaskButtons] ORPHANED BODY CLASSES:", activeClasses.join(", "));
    }

    // Log all <style> elements with IDs for audit
    var styles = document.querySelectorAll("style[id]");
    var styleIds = [];
    styles.forEach(function(s) { styleIds.push(s.id); });
    console.log("[TaskButtons] Active <style> IDs:", styleIds.join(", ") || "none");

    // Log page-head computed dimensions
    if (pageHead.length) {
        console.log("[TaskButtons] .page-head height:", pageHead[0].offsetHeight + "px", "| overflow:", pageHead.css("overflow"));
    }
    console.log("[TaskButtons] ─── End Debug ───");
}

// ── main event handler ─────────────────────────────────────────
frappe.ui.form.on("Task", {
    refresh(frm) {
        tab_cleanup_disabled_scripts();
        tab_inject_mobile_css();
        tab_mobile_scroll_to_top(frm);
        tab_dashboard_comments(frm);
        tab_render_subheader(frm);
        tab_render_bottom_actions(frm);
        tab_render_desktop_buttons(frm);
        tab_debug_header(frm);
    }
});
