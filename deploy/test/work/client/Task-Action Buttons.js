// Name: Task-Action Buttons
// DocType: Task
// Enabled: 1
// ---
// Unified button script for Task forms.
// Owns: Accept, Create DC, Open DC, Complete, multi-state (Delivery/Pickup Returns) (desktop header + mobile bottom floating).
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

// ── generic field-save with revert-on-error ─────────────────
// Sets one or more fields on the doc and saves via savedocs.
// On error, reverts all fields to their original values.
// Used by both Complete and multi-state transitions (Delivery, Pickup Returns).
function tab_do_save_fields(frm, btn, fields, busyText, freezeText) {
    if (btn && btn.data && btn.data("busy")) return;
    var originals = {};
    var originalLabel = btn ? btn.text() : "";
    Object.keys(fields).forEach(function(k) { originals[k] = frm.doc[k]; });
    if (btn) btn.data("busy", true).prop("disabled", true).text(busyText || "Saving...");

    Object.keys(fields).forEach(function(k) { frm.doc[k] = fields[k]; });
    frm.doc.__unsaved = 1;

    // Call savedocs directly via frappe.call — bypasses frm.save() which has
    // unreliable promise rejection and argument-signature issues.
    frappe.call({
        method: "frappe.desk.form.save.savedocs",
        args: { doc: frm.doc, action: "Save" },
        freeze: true,
        freeze_message: __(freezeText || "Saving..."),
        callback: function() {
            if (btn) btn.data("busy", false);
            frm.reload_doc();
        },
        error: function() {
            Object.keys(originals).forEach(function(k) { frm.doc[k] = originals[k]; });
            if (btn) btn.data("busy", false).prop("disabled", false).text(originalLabel);
        }
    });
}

function tab_do_complete_inner(frm, btn) {
    var fields = { status: "Completed" };
    if (!frm.doc.completed_on) fields.completed_on = frappe.datetime.get_today();
    tab_do_save_fields(frm, btn, fields, "Completing...", "Completing...");
}

function tab_do_complete(frm, btn) {
    if (btn && btn.data && btn.data("busy")) return;
    // Order entry: check for discounted items and warn before completing
    if (frm.doc.task_kind === "Order entry" && frm.doc.dispatch_case) {
        frappe.call({
            method: "frappe.client.get",
            args: { doctype: "Dispatch Case", name: frm.doc.dispatch_case },
            callback: function(r) {
                var dc = r.message;
                if (!dc) { tab_do_complete_inner(frm, btn); return; }
                var items = dc.case_items || [];
                var has_discount = items.some(function(row) { return flt(row.discount_pct || 0) > 0; });
                if (has_discount) {
                    frappe.confirm(
                        __("This order has discounted items and will require Director approval before packing. Continue?"),
                        function() { tab_do_complete_inner(frm, btn); }
                    );
                } else {
                    tab_do_complete_inner(frm, btn);
                }
            }
        });
    } else {
        tab_do_complete_inner(frm, btn);
    }
}

// ── primary action resolver ──────────────────────────────────
// Returns { label, color, handler(frm, btn) } or null.
// Multi-state tasks (Delivery, Pickup Returns) get state-specific buttons;
// all other task kinds get the generic Complete action.
function tab_get_primary_action(frm) {
    var kind = (frm.doc.task_kind || "").trim();

    // Delivery: Todo → "Picked Up" → "Delivered" (auto-completes on server)
    if (kind === "Delivery") {
        var ds = (frm.doc.delivery_status || "Todo").trim();
        if (ds === "Todo") {
            return { label: "Picked Up", color: "#e67e22", handler: function(frm2, btn) {
                tab_do_save_fields(frm2, btn, { delivery_status: "Picked Up" });
            }};
        }
        if (ds === "Picked Up") {
            return { label: "Delivered", color: "#27ae60", handler: function(frm2, btn) {
                tab_do_save_fields(frm2, btn, { delivery_status: "Delivered" });
            }};
        }
        return null;
    }

    // Pickup Returns: Todo → "Picked Up" → "Returned to WH" (auto-completes on server)
    if (kind === "Pickup Returns") {
        var ps = (frm.doc.pickup_status || "Todo").trim();
        if (ps === "Todo") {
            return { label: "Picked Up", color: "#e67e22", handler: function(frm2, btn) {
                tab_do_save_fields(frm2, btn, { pickup_status: "Picked Up" });
            }};
        }
        if (ps === "Picked Up") {
            return { label: "Returned to WH", color: "#27ae60", handler: function(frm2, btn) {
                tab_do_save_fields(frm2, btn, { pickup_status: "Returned to Warehouse" });
            }};
        }
        return null;
    }

    // All other task kinds: generic Complete
    return { label: "Complete", color: "#27ae60", handler: function(frm2, btn) {
        tab_do_complete(frm2, btn);
    }};
}

// ── dashboard comments (absorbed from Task-Dispatch Packing Usability) ──
function tab_dashboard_comments(frm) {
    frm.dashboard.clear_comment();
    if (frm.doc.dispatch_case && frm.doc.task_kind !== "Order entry") {
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

    // Open Dispatch Case
    if (frm.doc.dispatch_case) {
        var dcBtn = $('<button class="btn btn-default btn-sm" style="font-size:12px;padding:4px 8px;">View DC</button>');
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

        // Primary action — right (Complete, Picked Up, Delivered, etc.)
        var action = tab_get_primary_action(frm);
        if (action) {
            var actionBtn = $('<button style="pointer-events:auto;padding:14px 24px;font-size:15px;font-weight:bold;background:' + action.color + ';color:#fff;border:none;border-radius:12px;cursor:pointer;box-shadow:0 4px 12px rgba(0,0,0,0.25);margin-left:auto;">' + action.label + '</button>');
            actionBtn.on("click", function() { action.handler(frm, $(this)); });
            container.append(actionBtn);
        }
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

    // View DC — always if DC exists (smaller secondary link)
    if (hasDC) {
        frm.add_custom_button(__("View DC"), function() {
            frappe.set_route("Form", "Dispatch Case", frm.doc.dispatch_case);
        });
    }

    if (!isCompleted && !isCancelled) {
        // Primary action (Complete, Picked Up, Delivered, etc.)
        var action = tab_get_primary_action(frm);
        if (isAccepted && action) {
            frm.add_custom_button(__(action.label), function() {
                action.handler(frm, null);
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

// ── auto-fill client location warehouse ─────────────────────
// When Order Entry has return_expected checked and customer set but no
// warehouse selected, extract the client code from the customer name
// (e.g. "D148" from "D148 — Name — Hospital - Inmed") and find the
// first warehouse whose name starts with that code.
function tab_autofill_client_warehouse(frm) {
    console.log("[TaskButtons] Warehouse auto-fill check: kind=" + frm.doc.task_kind
        + " return_expected=" + frm.doc.order_return_expected
        + " customer=" + (frm.doc.customer || "(none)")
        + " warehouse=" + (frm.doc.order_client_location_warehouse || "(empty)"));
    if (frm.doc.task_kind !== "Order entry") return;
    if (!frm.doc.order_return_expected) return;
    if (!frm.doc.customer) return;
    if (frm.doc.order_client_location_warehouse) return;

    // Extract code from customer name: "D148 — Name — Hospital - Inmed" → "D148"
    var code = (frm.doc.customer.split(" \u2014 ")[0] || "").trim();
    if (!code) {
        console.log("[TaskButtons] Warehouse auto-fill: could not extract code from " + frm.doc.customer);
        return;
    }
    console.log("[TaskButtons] Warehouse auto-fill: extracted code=" + code + " from " + frm.doc.customer);

    frappe.call({
        method: "frappe.client.get_list",
        args: {
            doctype: "Warehouse",
            filters: { name: ["like", code + " %"] },
            fields: ["name"],
            limit_page_length: 1,
            order_by: "name asc"
        },
        callback: function(r) {
            var warehouses = r.message || [];
            if (warehouses.length && !frm.doc.order_client_location_warehouse) {
                frm.set_value("order_client_location_warehouse", warehouses[0].name);
                console.log("[TaskButtons] Warehouse auto-fill: code=" + code
                    + " matched=" + warehouses[0].name);
            } else {
                console.log("[TaskButtons] Warehouse auto-fill: code=" + code + " no match found");
            }
        }
    });
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
    },
    customer(frm) {
        tab_autofill_client_warehouse(frm);
    },
    order_return_expected(frm) {
        tab_autofill_client_warehouse(frm);
    }
});
