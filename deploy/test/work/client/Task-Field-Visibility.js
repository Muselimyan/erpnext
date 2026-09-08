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
// "__add_product__"       -> visible when Order entry + has dispatch_case
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

    // Barcode Scanning (same as product)
    "custom_barcode_section":       "__product__",
    "custom_task_scan_barcode":     "__product__",
    "custom_task_scan_qty":         "__product__",
    "custom_task_scan_result":      "__product__",

    // Manual Product Add -- Order entry ONLY (not Pack, not Returns)
    "custom_task_add_item_code":    "__add_product__",
    "custom_task_add_qty":          "__add_product__",
    "custom_task_add_batch_no":     "__add_product__",
    "custom_task_add_unit_price":   "__add_product__"
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
    var is_add = (kind === "Order entry" && !!frm.doc.dispatch_case);
    var is_completed = frm.doc.status === "Completed";
    var is_mobile = window.innerWidth <= 768;
    var is_dispatch = TFV_DISPATCH_FLOW_KINDS.indexOf(kind) !== -1;

    // Always-hidden
    TFV_ALWAYS_HIDDEN.forEach(function(f) {
        if (frm.fields_dict[f]) frm.toggle_display(f, false);
    });

    // Per-field visibility
    Object.keys(TFV_KIND_MAP).forEach(function(fieldname) {
        if (!frm.fields_dict[fieldname]) return;
        var rule = TFV_KIND_MAP[fieldname];
        var visible = false;
        if (rule === "__all__")                    visible = true;
        else if (rule === "__never__")             visible = false;
        else if (rule === "__completed__")         visible = is_completed;
        else if (rule === "__product__")           visible = is_product;
        else if (rule === "__add_product__")       visible = is_add;
        else if (rule === "__has_value__")         visible = !!frm.doc[fieldname];
        else if (rule === "__dispatch_or_value__") visible = is_dispatch || !!frm.doc[fieldname];
        else if (rule === "__order_return__")      visible = (kind === "Order entry" && !!frm.doc.order_return_expected);
        else if (Array.isArray(rule))              visible = rule.indexOf(kind) !== -1;
        frm.toggle_display(fieldname, visible);
    });

    // task_kind: read-only after first save
    if (!frm.is_new()) {
        frm.set_df_property("task_kind", "read_only", 1);
    }

    // Description: collapsible for dispatch-flow tasks
    // "description" is a Text Editor inside section break "sb_details".
    // collapsible is a Section Break property, so target the parent section.
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
    }

    // Activity/Timeline: hidden on mobile (DOM exception -- principle #7)
    if (is_mobile) {
        $(frm.wrapper).find(".form-footer .timeline-group, .form-footer .timeline-actions").hide();
        $(frm.wrapper).find(".section-head:contains('Activity')").closest(".form-section").hide();
    }

    // Photo gallery: set flag for Task-Photo-System.js (DOM exception -- principle #7)
    frm._tfv_show_gallery = TFV_PHOTO_GALLERY_KINDS.indexOf(kind) !== -1;
    if (!frm._tfv_show_gallery) {
        $(frm.wrapper).find('[id^="photo-gallery-host-"]').hide();
    }
}

frappe.ui.form.on("Task", {
    refresh: function(frm) { tfv_apply(frm); },
    task_kind: function(frm) { tfv_apply(frm); },
    dispatch_case: function(frm) { tfv_apply(frm); },
    order_return_expected: function(frm) { tfv_apply(frm); }
});
