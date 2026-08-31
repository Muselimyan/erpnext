// Name: Task-Action Buttons
// DocType: Task
// Enabled: 1
// ---
// Unified button script for Task forms.
// Owns: Accept, Create DC, Open DC, Complete (desktop header + mobile bottom floating).
// Mobile sub-header bar: Back, Refresh, Open DC, Products.
// Replaces buttons previously in Task-Accept Start, Task-Create Dispatch Case Items,
// Task-Dispatch Packing Usability.

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
    var timeoutId = setTimeout(function() {
        frm.doc.status = originalStatus;
        frm.doc.completed_on = originalCompletedOn || "";
        if (btn) btn.data("busy", false).prop("disabled", false).text("Complete");
        frappe.show_alert({message: __("Complete Task timed out. Please try again."), indicator: "red"}, 10);
    }, 30000);

    // Single save: set status + save in one call. No intermediate refresh.
    // Use callback style — frm.save() promises do NOT reliably reject on
    // server validation errors (frappe.throw). The on_error callback does fire.
    frm.doc.status = "Completed";
    if (!frm.doc.completed_on) frm.doc.completed_on = frappe.datetime.get_today();
    frm.dirty();
    frm.save(
        function() {
            clearTimeout(timeoutId);
            // frm.save() already updated doc and fired refresh — form shows completed state.
        },
        null,
        function() {
            clearTimeout(timeoutId);
            frm.doc.status = originalStatus;
            frm.doc.completed_on = originalCompletedOn || "";
            if (btn) btn.data("busy", false).prop("disabled", false).text("Complete");
        }
    );
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

// ── main event handler ─────────────────────────────────────────
frappe.ui.form.on("Task", {
    refresh(frm) {
        tab_dashboard_comments(frm);
        tab_render_subheader(frm);
        tab_render_bottom_actions(frm);
        tab_render_desktop_buttons(frm);
    }
});
