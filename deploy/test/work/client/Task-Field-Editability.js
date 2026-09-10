// Name: Task-Field-Editability
// DocType: Task
// Enabled: 1
// ---
// Single source of truth for Task form field editability.
// Analogous to Task-Field-Visibility.js (TFV) for visibility.
// Absorbs: Task-Lock Unaccepted, Task-Lock Completed (both now disabled).
// No admin exemption — must be accepted by current user to edit.
// See: docs/21-product-section-architecture.md

// ═══════════════════════════════════════════════════════════════
// Section 1: Core editability gate
// ═══════════════════════════════════════════════════════════════

// Global function — other scripts (PWA, Action Buttons, Photo-System) use this.
function tfe_can_edit(frm) {
    if (!frm || !frm.doc) return false;
    if (frm.is_new()) return true;
    if (frm.doc.status === "Completed" || frm.doc.status === "Cancelled") return false;
    var accepted_by = (frm.doc.custom_accepted_by || "").trim();
    return accepted_by === frappe.session.user;
}

// ═══════════════════════════════════════════════════════════════
// Section 2: Per-field editability map
// ═══════════════════════════════════════════════════════════════

// Rule types:
// "__never__"       → always read-only after save
// "__accepted__"    → editable when tfe_can_edit(frm) returns true [default for unmapped fields]
// [array of kinds]  → editable ONLY when kind is in the array AND tfe_can_edit(frm)

var TFE_EDIT_MAP = {
    // ── Always read-only (system-managed, auto-set fields) ──────
    "task_kind":             "__never__",
    "completed_at":          "__never__",
    "dispatch_case":         "__never__",
    "delivery_status":       "__never__",
    "pickup_status":         "__never__",
    "dispatch_case_status":  "__never__",
    "sales_invoice":         "__never__",
    "payment_entry":         "__never__",

    // ── Informational display (visible for context, not editable) ──
    "current_debt_amd":         "__never__",
    "debt_threshold_amd":       "__never__",
    "total_outstanding":        "__never__",
    "available_advance_credit": "__never__",
    "custom_case_profit":       "__never__",
    "custom_total_amount_paid": "__never__",
    "open_invoices":            "__never__",
    "payment_history":          "__never__",

    // ── Kind-specific editability (requires acceptance AND kind match) ──
    "customer":                        ["Order entry", "Other: Entry", "Other: Processing"],
    "order_return_expected":           ["Order entry"],
    "order_client_location_warehouse": ["Order entry"],
    "order_surgery_date":              ["Order entry"],
    "order_template":                  ["Order entry"],
    "approval_outcome":  ["Purchase Approval", "Discount Approval",
                          "Write-off Approval", "Debt Closure Approval"],
    "approval_note":     ["Purchase Approval", "Discount Approval",
                          "Write-off Approval", "Debt Closure Approval"],
    "purchase_order":    ["Purchase Approval"],
    "new_payment_amount":   ["Payment Received", "Debt Collection"],
    "payment_method_dc":    ["Payment Received", "Debt Collection"],
    "payment_reference_dc": ["Payment Received", "Debt Collection"],
    "return_pickup_driver":  ["Pickup Returns", "Return drop-off at warehouse",
                              "Return to warehouse (aborted delivery / cancelled order)"],
    "scheduled_return_date": ["Pickup Returns", "Return drop-off at warehouse"],
    "other_items":    ["Other: Entry", "Other: Processing"],
    "other_budget":   ["Other: Entry", "Other: Processing"],
    "other_supplier": ["Other: Entry", "Other: Processing"]
};

// Fields to skip when applying blanket editability (structural, not data fields)
var TFE_SKIP_TYPES = ["Section Break", "Column Break", "Tab Break"];

// ═══════════════════════════════════════════════════════════════
// Section 3: Main apply function
// ═══════════════════════════════════════════════════════════════

function tfe_apply(frm) {
    if (!frm || frm.doctype !== "Task") return;

    var can_edit = tfe_can_edit(frm);
    var kind = (frm.doc.task_kind || "").trim();
    var is_completed = frm.doc.status === "Completed";
    var is_cancelled = frm.doc.status === "Cancelled";
    var is_new = frm.is_new();

    console.log("[TFE] ═══ tfe_apply START ═══ task=" + frm.doc.name
        + " kind=\"" + kind + "\""
        + " status=" + frm.doc.status
        + " accepted_by=" + (frm.doc.custom_accepted_by || "(none)")
        + " user=" + frappe.session.user
        + " can_edit=" + can_edit);

    // ── Intro messages ──────────────────────────────────────────
    frm.set_intro("");
    if (!is_new) {
        if (is_completed) {
            frm.set_intro("This task is completed and cannot be modified.", "green");
        } else if (is_cancelled) {
            frm.set_intro("This task is cancelled and cannot be modified.", "red");
        } else if (!can_edit) {
            frm.set_intro('You must accept this task before you can edit it. Click <b>Accept / Start Task</b>.', "yellow");
        }
    }

    // ── Save button ─────────────────────────────────────────────
    if (can_edit) {
        frm.enable_save();
    } else if (!is_new) {
        frm.disable_save();
    }

    // ── Per-field editability ───────────────────────────────────
    // Track which fields we set via TFE_EDIT_MAP so we can apply
    // the blanket default to the rest.
    var mapped_fields = {};

    Object.keys(TFE_EDIT_MAP).forEach(function(fieldname) {
        mapped_fields[fieldname] = true;
        if (!frm.fields_dict[fieldname]) return;

        var rule = TFE_EDIT_MAP[fieldname];
        var editable = false;
        var reason = "";

        if (rule === "__never__") {
            editable = false;
            reason = "__never__";
        } else if (rule === "__accepted__") {
            editable = can_edit;
            reason = "__accepted__ (can_edit=" + can_edit + ")";
        } else if (Array.isArray(rule)) {
            editable = can_edit && rule.indexOf(kind) !== -1;
            reason = "array (can_edit=" + can_edit + " kind=\"" + kind + "\" in [" + rule.join(", ") + "] = " + editable + ")";
        } else {
            reason = "UNKNOWN rule: " + JSON.stringify(rule);
        }

        frm.set_df_property(fieldname, "read_only", editable ? 0 : 1);
        console.log("[TFE] " + (editable ? "EDIT" : "LOCK") + ": " + fieldname + " | rule=" + reason);
    });

    // ── Blanket: fields NOT in the map default to can_edit ──────
    (frm.fields || []).forEach(function(field) {
        if (!field.df || !field.df.fieldname) return;
        if (TFE_SKIP_TYPES.indexOf(field.df.fieldtype) !== -1) return;
        if (mapped_fields[field.df.fieldname]) return;

        frm.set_df_property(field.df.fieldname, "read_only", can_edit ? 0 : 1);
    });

    frm.refresh_fields();

    // ── DOM-level disable (catch-all for non-Frappe controls) ───
    // This covers HTML inputs/selects that Frappe's read_only doesn't touch,
    // but excludes the product summary area (PWA handles that separately).
    if (!can_edit && !is_new) {
        $(frm.wrapper).find('input, textarea, select, .ql-editor, .like-disabled-input')
            .not('#task-product-summary-wrapper input, #task-product-summary-wrapper textarea, #task-product-summary-wrapper select')
            .prop("disabled", true)
            .css({"pointer-events": "none", "opacity": "0.6", "background-color": "#f5f5f5"});
        $(frm.wrapper).find('.btn-attach, .btn-open, .grid-add-row, .grid-remove-rows').hide();
    } else if (can_edit) {
        $(frm.wrapper).find('input, textarea, select, .ql-editor, .like-disabled-input')
            .not('#task-product-summary-wrapper input, #task-product-summary-wrapper textarea, #task-product-summary-wrapper select')
            .prop("disabled", false)
            .css({"pointer-events": "", "opacity": "", "background-color": ""});
        $(frm.wrapper).find('.btn-attach, .btn-open, .grid-add-row, .grid-remove-rows').show();
    }

    // ── Photo galleries ─────────────────────────────────────────
    if (frm._photoGalleries) {
        Object.values(frm._photoGalleries).forEach(function(g) {
            if (can_edit && g._configEditable) {
                g.setMode("editable");
            } else {
                g.setMode("readonly");
            }
        });
    }

    console.log("[TFE] ═══ tfe_apply END ═══");
}

// ═══════════════════════════════════════════════════════════════
// Section 4: Event handler
// ═══════════════════════════════════════════════════════════════

frappe.ui.form.on("Task", {
    refresh: function(frm) {
        tfe_apply(frm);
    },
    custom_accepted_by: function(frm) {
        tfe_apply(frm);
    }
});
