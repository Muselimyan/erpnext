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

    // Dispatch Case
    "dispatch_case":    ["Order entry", "Pack / prepare items",
                         "Dispatch picking / hand-off", "Delivery",
                         "Return Call",
                         "Return to warehouse (aborted delivery / cancelled order)",
                         "Pickup Returns", "Return drop-off at warehouse",
                         "Returns processing / verification",
                         "Returns restocking",
                         "Invoice preparation / create invoice",
                         "Discount Approval",
                         "Debt Collection", "Distribute Payment",
                         "Payment Received", "Debt Closure Approval",
                         "Dispatch Cancel Restock"],

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
    // NOTE: custom_product_work_column is a Column Break -- inherits from
    // parent section, do NOT toggle individually
    "custom_task_product_warning":  "__product__",

    // Scan fields -- Pack/Returns only (not Order entry)
    "custom_task_scan_barcode":     "__scan_product__",
    "custom_task_scan_qty":         "__scan_product__",
    "custom_task_scan_result":      "__scan_product__"
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

    // task_kind: read-only after first save
    if (!frm.is_new()) {
        frm.set_df_property("task_kind", "read_only", 1);
    }

    // Description: collapsible for dispatch-flow tasks
    var sb = frm.fields_dict.sb_details;
    if (sb) {
        var has_text = !!(frm.doc.description || "").trim();
        if (is_dispatch) {
            sb.df.collapsible = 1;
            sb.collapse(!has_text);
        } else {
            sb.df.collapsible = 0;
            sb.collapse(false);
        }
        sb.refresh();
        console.log("[TFV] description section: collapsible=" + sb.df.collapsible + " collapsed=" + !has_text);
    }

    // Activity/Timeline: hidden on mobile
    if (is_mobile) {
        $(frm.wrapper).find(".form-footer .timeline-group, .form-footer .timeline-actions").hide();
        $(frm.wrapper).find(".section-head:contains('Activity')").closest(".form-section").hide();
        console.log("[TFV] mobile: hid Activity/Timeline");
    }

    // Photo gallery flag
    frm._tfv_show_gallery = TFV_PHOTO_GALLERY_KINDS.indexOf(kind) !== -1;
    if (!frm._tfv_show_gallery) {
        $(frm.wrapper).find('[id^="photo-gallery-host-"]').hide();
    }
    console.log("[TFV] photo gallery: show=" + frm._tfv_show_gallery);

    // Dynamic labels/descriptions per task kind
    if (kind === "Order entry") {
        frm.set_df_property("dispatch_case", "label", "Dispatch Case");
        frm.set_df_property("dispatch_case", "description",
            "Auto-created on task acceptance. Products you add are stored here.");
        frm.set_df_property("custom_product_work_section", "label", "Products");
    } else if (kind === "Pack / prepare items") {
        frm.set_df_property("dispatch_case", "label", "Dispatch Case / Packing Items");
        frm.set_df_property("dispatch_case", "description",
            "Open to view batch/LOT, expiry, scanned qty, FEFO warnings, and packing problems.");
        frm.set_df_property("custom_product_work_section", "label", "Products / Packing");
    } else if (kind === "Returns processing / verification") {
        frm.set_df_property("dispatch_case", "label", "Dispatch Case");
        frm.set_df_property("dispatch_case", "description",
            "Open to view product rows and return quantities.");
        frm.set_df_property("custom_product_work_section", "label", "Products / Returns");
    } else if (is_dispatch) {
        frm.set_df_property("dispatch_case", "label", "Dispatch Case");
        frm.set_df_property("dispatch_case", "description", "");
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
