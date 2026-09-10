// Name: Task-Field-Visibility
// DocType: Task
// Enabled: 1
// ---
// Single source of truth for Task form field/section visibility.
// Other scripts must NOT toggle field visibility.
// See: deploy/test/work/task-field-visibility-redesign.md

// ── Always-hidden fields (internal, legacy, removed) ─────────
var TFV_ALWAYS_HIDDEN = [
    // Internal
    "task_access_policy", "dispatch_group_id",
    "custom_accepted_by", "custom_accepted_at",
    // Standard fields (hidden via property setters too)
    "status", "priority",
    "project", "issue", "type", "color",
    "is_group", "task_weight", "parent_task", "is_template"
    // Phase 9: removed 6 deleted fields (driver_handover_note,
    // custom_account_details_section, custom_account_details_subject,
    // custom_account_photos, custom_account_details_entry_task,
    // custom_product_lines) — no longer in schema.
];

// ── Rule types ────────────────────────────────────────────────
// "__all__"               -> always visible
// "__never__"             -> always hidden
// "__completed__"         -> visible only when status === "Completed"
// "__product__"           -> visible when tfv_is_product_task(frm)
// "__scan_product__"      -> visible when Pack/Returns + has dispatch_case
// "__has_value__"         -> visible when field has a truthy value
// "__dispatch_or_value__" -> visible for dispatch-flow kind OR when has value
// "__order_return__"      -> visible when Order entry + return_expected checked
// [array]                 -> visible when kind is in the array

// ── Visibility map: field -> rule ─────────────────────────────
var TFV_KIND_MAP = {
    // Core
    "subject":          "__all__",
    "task_kind":        "__all__",
    "completed_at":     "__completed__",

    // Assignment
    "custom_assigned_to":           "__all__",
    "custom_next_task_assign_to":   ["Order entry", "Pack / prepare items", "Delivery",
                                     "Return Call", "Pickup Returns",
                                     "Returns processing / verification",
                                     "Discount Approval", "Other: Entry"],

    // Customer
    "customer":         "__dispatch_or_value__",

    // Order Entry fields (Dispatch Redesign v4 -- not yet in schema, safe no-ops)
    "order_return_expected":            ["Order entry"],
    "order_client_location_warehouse":  "__order_return__",
    "order_surgery_date":               ["Order entry"],
    "order_template":                   ["Order entry"],

    // Dispatch Case — always hidden (View DC button covers navigation)
    "dispatch_case":    "__never__",

    // Status dropdowns -- always hidden (replaced by buttons)
    "delivery_status":      "__never__",
    "pickup_status":        "__never__",
    "dispatch_case_status": "__never__",

    // Approval
    "purchase_order":   ["Purchase Approval"],
    "approval_outcome": ["Purchase Approval", "Discount Approval",
                         "Write-off Approval", "Debt Closure Approval"],
    "approval_note":    ["Purchase Approval", "Discount Approval",
                         "Write-off Approval", "Debt Closure Approval"],

    // Invoice / Sales -- value-based
    "sales_invoice":    "__has_value__",

    // Payment / Debt
    "payment_entry":            "__has_value__",
    "current_debt_amd":         ["Debt Collection"],
    "debt_threshold_amd":       ["Debt Collection"],
    "new_payment_amount":       ["Payment Received", "Debt Collection"],
    "payment_method_dc":        ["Payment Received", "Debt Collection"],
    "payment_reference_dc":     ["Payment Received", "Debt Collection"],
    "total_outstanding":        ["Debt Collection", "Distribute Payment", "Debt Closure Approval"],
    "available_advance_credit": ["Debt Collection", "Distribute Payment", "Debt Closure Approval"],
    "custom_case_profit":       ["Debt Collection", "Distribute Payment", "Debt Closure Approval"],
    "custom_total_amount_paid": ["Debt Collection", "Distribute Payment", "Debt Closure Approval"],
    "open_invoices":            ["Debt Collection", "Distribute Payment", "Debt Closure Approval"],
    "payment_history":          ["Debt Collection", "Distribute Payment", "Debt Closure Approval"],

    // Returns
    "return_pickup_driver":  ["Pickup Returns", "Return drop-off at warehouse",
                              "Return to warehouse (aborted delivery / cancelled order)"],
    "scheduled_return_date": ["Pickup Returns", "Return drop-off at warehouse"],

    // Other
    "other_items":    ["Other: Entry", "Other: Processing"],
    "other_budget":   ["Other: Entry", "Other: Processing"],
    "other_supplier": ["Other: Entry", "Other: Processing"],

    // Product Work Section (Pack, Returns proc, Order entry with DC)
    "custom_product_work_section":  "__product__",
    "custom_task_product_summary":  "__product__",

    // Scan fields -- Pack/Returns only (not Order entry)
    "custom_task_scan_barcode":     "__scan_product__",
    "custom_task_scan_qty":         "__scan_product__",
    "custom_task_scan_result":      "__scan_product__",

    // Standard fields (hidden via property setters, shown by TFV)
    "sb_details":   "__all__",
    "description":  "__all__"
};

// ── Photo gallery kinds (consumed by Task-Photo-System.js) ────
var TFV_PHOTO_GALLERY_KINDS = [
    "Pack / prepare items",
    "Pickup Returns",
    "Returns processing / verification",
    "Other: Entry",
    "Other: Processing"
];

// ── Product task classification ───────────────────────────────
var TFV_PRODUCT_EDIT_KINDS = [
    "Pack / prepare items",
    "Returns processing / verification"
];

function tfv_is_product_task(frm) {
    if (TFV_PRODUCT_EDIT_KINDS.indexOf(frm.doc.task_kind) !== -1) return true;
    if (frm.doc.task_kind === "Order entry" && !!frm.doc.dispatch_case) return true;
    return false;
}

// ── Scan-only product classification (Pack/Returns, not Order entry) ──
var TFV_SCAN_PRODUCT_KINDS = [
    "Pack / prepare items",
    "Returns processing / verification"
];

function tfv_is_scan_product_task(frm) {
    return TFV_SCAN_PRODUCT_KINDS.indexOf(frm.doc.task_kind) !== -1
        && !!frm.doc.dispatch_case;
}

// ── Dispatch flow kinds (description collapsible for these) ───
var TFV_DISPATCH_FLOW_KINDS = [
    "Order entry", "Pack / prepare items", "Dispatch picking / hand-off",
    "Delivery", "Return Call",
    "Return to warehouse (aborted delivery / cancelled order)",
    "Pickup Returns", "Return drop-off at warehouse",
    "Returns processing / verification", "Returns restocking",
    "Invoice preparation / create invoice",
    "Discount Approval", "Debt Closure Approval",
    "Debt Collection", "Distribute Payment", "Payment Received",
    "Dispatch Cancel Restock"
];

// ── Main visibility function ──────────────────────────────────
function tfv_apply(frm) {
    if (!frm || frm.doctype !== "Task") return;
    var kind = (frm.doc.task_kind || "").trim();
    var is_product = tfv_is_product_task(frm);
    var is_scan = tfv_is_scan_product_task(frm);
    var is_completed = frm.doc.status === "Completed";
    var is_mobile = window.innerWidth <= 768;
    var is_dispatch = TFV_DISPATCH_FLOW_KINDS.indexOf(kind) !== -1;

    console.log("[TFV] ═══ tfv_apply START ═══ task=" + frm.doc.name
        + " kind=\"" + kind + "\""
        + " status=" + frm.doc.status
        + " dc=" + (frm.doc.dispatch_case || "(none)")
        + " mobile=" + is_mobile);
    console.log("[TFV] flags: is_product=" + is_product
        + " is_scan=" + is_scan
        + " is_completed=" + is_completed
        + " is_dispatch=" + is_dispatch);

    // Always-hidden
    TFV_ALWAYS_HIDDEN.forEach(function(f) {
        if (frm.fields_dict[f]) {
            frm.toggle_display(f, false);
            console.log("[TFV] ALWAYS_HIDDEN: " + f + " -> HIDE");
        }
    });

    // Per-field visibility
    Object.keys(TFV_KIND_MAP).forEach(function(fieldname) {
        if (!frm.fields_dict[fieldname]) {
            console.warn("[TFV] MISSING field: " + fieldname + " (not in fields_dict)");
            return;
        }
        var rule = TFV_KIND_MAP[fieldname];
        var visible = false;
        var reason = "";
        if (rule === "__all__") {
            visible = true;
            reason = "__all__";
        } else if (rule === "__never__") {
            visible = false;
            reason = "__never__";
        } else if (rule === "__completed__") {
            visible = is_completed;
            reason = "__completed__ (is_completed=" + is_completed + ")";
        } else if (rule === "__product__") {
            visible = is_product;
            reason = "__product__ (is_product=" + is_product + ")";
        } else if (rule === "__scan_product__") {
            visible = is_scan;
            reason = "__scan_product__ (is_scan=" + is_scan + ")";
        } else if (rule === "__has_value__") {
            visible = !!frm.doc[fieldname];
            reason = "__has_value__ (val=" + JSON.stringify(frm.doc[fieldname]) + ")";
        } else if (rule === "__dispatch_or_value__") {
            visible = is_dispatch || !!frm.doc[fieldname];
            reason = "__dispatch_or_value__ (is_dispatch=" + is_dispatch + " val=" + JSON.stringify(frm.doc[fieldname]) + ")";
        } else if (rule === "__order_return__") {
            visible = (kind === "Order entry" && !!frm.doc.order_return_expected);
            reason = "__order_return__ (kind=" + kind + " ret_exp=" + frm.doc.order_return_expected + ")";
        } else if (Array.isArray(rule)) {
            visible = rule.indexOf(kind) !== -1;
            reason = "array (kind \"" + kind + "\" in [" + rule.join(", ") + "] = " + visible + ")";
        } else {
            reason = "UNKNOWN rule: " + JSON.stringify(rule);
        }
        frm.toggle_display(fieldname, visible);
        console.log("[TFV] " + (visible ? "SHOW" : "HIDE") + ": " + fieldname
            + " | rule=" + reason
            + " | df.hidden=" + frm.fields_dict[fieldname].df.hidden
            + " | wrapper=" + (frm.fields_dict[fieldname].$wrapper ? frm.fields_dict[fieldname].$wrapper.css("display") : "no$w"));
    });

    // task_kind read-only: moved to Task-Field-Editability.js (TFE)
    // TFE owns all editability decisions.

    // ── Details section: native Frappe collapsible for ALL tasks ──
    // sb_details has Property Setters: hidden=1 (TFV shows via __all__), collapsible=1.
    // Frappe renders the section with a chevron + click handler.
    // Collapsed by default for all tasks. User can click to expand.
    var sb = frm.fields_dict.sb_details;
    if (sb) {
        // Ensure collapsible is set (Property Setter should have done this)
        sb.df.collapsible = 1;
        sb.refresh();
        // Collapse after refresh -- reliable because section was born collapsible
        if (typeof sb.collapse === "function") {
            sb.collapse(true);
            console.log("[TFV] Details section: COLLAPSED via native sb.collapse(true)"
                + " | collapsible=" + sb.df.collapsible
                + " | has_body=" + !!(sb.body)
                + " | body_visible=" + (sb.body ? $(sb.body).is(':visible') : 'no-body'));
        } else {
            // Fallback: DOM-based collapse
            var $detailsHead = $(frm.wrapper).find('.section-head:contains("Details")');
            if ($detailsHead.length) {
                $detailsHead.closest('.form-section').find('.section-body').hide();
                console.log("[TFV] Details section: COLLAPSED via DOM fallback (no .collapse method)");
            } else {
                console.warn("[TFV] Details section: no .collapse method AND no 'Details' section-head");
            }
        }
    } else {
        console.warn("[TFV] Details section: frm.fields_dict.sb_details not found");
    }

    // ── Comments: collapsible in form footer (ALL tasks) ──
    // DOM: .comment-box > .comment-input-wrapper > .comment-input-header + .comment-input-container
    // .comment-input-header has "Comments" title — keep visible as toggle.
    // .comment-input-container has the Quill editor — hide by default.
    var $footer = $(frm.wrapper).find('.form-footer');
    console.log("[TFV] form-footer found=" + $footer.length);
    if ($footer.length) {
        var $commentBox = $footer.find('.comment-box');
        console.log("[TFV] Comments: .comment-box found=" + $commentBox.length);
        if ($commentBox.length) {
                var $commentHeader = $commentBox.find('.comment-input-header');
                var $commentContent = $commentBox.find('.comment-input-container');
                console.log("[TFV] Comments: header found=" + $commentHeader.length
                    + " | content found=" + $commentContent.length
                    + " | content visible=" + $commentContent.is(':visible'));
                // Collapse content by default
                $commentContent.hide();
                // Add collapse indicator if not already present
                if (!$commentHeader.find('.tfv-indicator').length) {
                    $commentHeader.find('.comment-title').after(
                        '<span class="tfv-indicator" style="margin-left:6px;font-size:11px;color:var(--text-muted)">▸</span>'
                    );
                    console.log("[TFV] Comments: added collapse indicator");
                }
                $commentHeader.css('cursor', 'pointer');
                // Bind click toggle (once per form load)
                if (!$commentHeader.data('tfv-bound')) {
                    $commentHeader.on('click.tfv', function() {
                        $commentContent.toggle();
                        var $ind = $commentHeader.find('.tfv-indicator');
                        $ind.text($commentContent.is(':visible') ? '▾' : '▸');
                        console.log("[TFV] Comments: toggled to " + ($commentContent.is(':visible') ? 'EXPANDED' : 'COLLAPSED'));
                    });
                    $commentHeader.data('tfv-bound', true);
                    console.log("[TFV] Comments: click handler bound");
                }
                console.log("[TFV] Comments: COLLAPSED (content hidden, header clickable)");
            }

        // ── Activity: collapsible in form footer (ALL tasks) ──
        // DOM: .new-timeline > .activity-title (h4 + .timeline-actions) + .timeline-items
        // h4 "Activity" — keep visible as toggle.
        // .timeline-actions (New Email button) — hide by default.
        // .timeline-items (direct child of .new-timeline, the actual events) — hide by default.
        var $newTimeline = $footer.find('.new-timeline');
        console.log("[TFV] Activity: .new-timeline found=" + $newTimeline.length);
        if ($newTimeline.length) {
            var $actH4 = $newTimeline.find('h4').first();
            var $actActions = $newTimeline.find('.timeline-actions');
            // .timeline-items direct child of .new-timeline = actual events
            // (not .timeline-actions which also has class .timeline-items but is inside .activity-title)
            var $actEvents = $newTimeline.children('.timeline-items');
            console.log("[TFV] Activity: h4 found=" + $actH4.length
                + " | .timeline-actions found=" + $actActions.length
                + " | direct .timeline-items children=" + $actEvents.length);
            // Collapse by default
            $actActions.hide();
            $actEvents.hide();
            // Add collapse indicator if not already present
            if (!$actH4.find('.tfv-indicator').length) {
                $actH4.append(
                    '<span class="tfv-indicator" style="margin-left:6px;font-size:11px;color:var(--text-muted)">▸</span>'
                );
                console.log("[TFV] Activity: added collapse indicator");
            }
            $actH4.css('cursor', 'pointer');
            // Bind click toggle (once per form load)
            if (!$actH4.data('tfv-bound')) {
                $actH4.on('click.tfv', function() {
                    $actActions.toggle();
                    $actEvents.toggle();
                    var $ind = $actH4.find('.tfv-indicator');
                    $ind.text($actEvents.is(':visible') ? '▾' : '▸');
                    console.log("[TFV] Activity: toggled to " + ($actEvents.is(':visible') ? 'EXPANDED' : 'COLLAPSED'));
                });
                $actH4.data('tfv-bound', true);
                console.log("[TFV] Activity: click handler bound");
            }
            console.log("[TFV] Activity: COLLAPSED (actions+events hidden, h4 clickable)");
        }
    }

    // ── Diagnostic: log all section heads in the DOM ──
    var $allHeads = $(frm.wrapper).find('.section-head');
    console.log("[TFV] DOM section-head inventory: " + $allHeads.length + " found");
    $allHeads.each(function(i) {
        var $h = $(this);
        var $sec = $h.closest('.form-section');
        var $body = $sec.find('.section-body');
        console.log("[TFV]   head[" + i + "] text='" + $.trim($h.text()) + "'"
            + " | .form-section=" + ($sec.length ? "yes" : "no")
            + " | .section-body=" + $body.length
            + " | body-visible=" + $body.filter(':visible').length
            + " | section-display=" + $sec.css('display'));
    });

    // Photo gallery flag
    frm._tfv_show_gallery = TFV_PHOTO_GALLERY_KINDS.indexOf(kind) !== -1;
    if (!frm._tfv_show_gallery) {
        $(frm.wrapper).find('[id^="photo-gallery-host-"]').hide();
    }
    console.log("[TFV] photo gallery: show=" + frm._tfv_show_gallery);

    // Dynamic section labels per task kind
    if (kind === "Order entry") {
        frm.set_df_property("custom_product_work_section", "label", "Products");
    } else if (kind === "Pack / prepare items") {
        frm.set_df_property("custom_product_work_section", "label", "Products / Packing");
    } else if (kind === "Returns processing / verification") {
        frm.set_df_property("custom_product_work_section", "label", "Products / Returns");
    } else if (is_dispatch) {
        frm.set_df_property("custom_product_work_section", "label", "Products / Dispatch Work");
    }

    console.log("[TFV] ═══ tfv_apply END ═══");
}

frappe.ui.form.on("Task", {
    refresh: function(frm) { tfv_apply(frm); },
    task_kind: function(frm) { tfv_apply(frm); },
    dispatch_case: function(frm) { tfv_apply(frm); },
    order_return_expected: function(frm) { tfv_apply(frm); }
});
