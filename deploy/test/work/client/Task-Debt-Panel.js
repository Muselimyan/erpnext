// Name: Task-Debt-Panel
// DocType: Task
// Enabled: 1
// ---
// Renders live customer debt on Debt Collection and Debt Closure Approval
// tasks, read from the ledger via the task_debt_panel API.
//
// Replaces the open_invoices / payment_history grids and the total_outstanding,
// available_advance_credit and custom_total_amount_paid fields, all of which
// stored a second copy of the receivables ledger on the Task and drifted from
// it. Nothing here is stored: the panel is recomputed every time the form is
// opened, so it cannot go stale.
//
// Visibility of custom_debt_panel itself is owned by Task-Field-Visibility.js
// (TFV). This script only fills it in.
//
// Log tag: [DebtPanel]

var TDP_KINDS = ["Debt Collection", "Debt Closure Approval"];

function tdp_money(v) {
    var n = Number(v || 0);
    return n.toLocaleString("en-US", { minimumFractionDigits: 0, maximumFractionDigits: 2 });
}

function tdp_render(frm, data) {
    var wrapper = frm.fields_dict.custom_debt_panel;
    if (!wrapper || !wrapper.$wrapper) return;

    if (!data || !data.customer) {
        wrapper.$wrapper.html('<div class="text-muted" style="padding:8px 0;">'
            + (data && data.note ? frappe.utils.escape_html(data.note) : "No customer on this task.")
            + '</div>');
        return;
    }

    var t = data.totals || {};
    var esc = frappe.utils.escape_html;

    // ── Totals strip ────────────────────────────────────────────────
    var html = '<div style="display:flex;flex-wrap:wrap;gap:10px;margin-bottom:12px;">';
    html += '<div style="flex:1;min-width:140px;border:1px solid var(--border-color,#d1d8dd);border-radius:8px;padding:10px;">'
        + '<div style="font-size:11px;color:var(--text-muted,#6c7680);text-transform:uppercase;">Outstanding</div>'
        + '<div style="font-size:19px;font-weight:600;">' + tdp_money(t.outstanding) + '</div></div>';
    html += '<div style="flex:1;min-width:140px;border:1px solid var(--border-color,#d1d8dd);border-radius:8px;padding:10px;">'
        + '<div style="font-size:11px;color:var(--text-muted,#6c7680);text-transform:uppercase;">Unallocated Credit</div>'
        + '<div style="font-size:19px;font-weight:600;">' + tdp_money(t.unallocated_credit) + '</div></div>';
    html += '<div style="flex:1;min-width:140px;border:1px solid var(--border-color,#d1d8dd);border-radius:8px;padding:10px;background:var(--fg-color,#fff);">'
        + '<div style="font-size:11px;color:var(--text-muted,#6c7680);text-transform:uppercase;">Net Receivable</div>'
        + '<div style="font-size:19px;font-weight:700;">' + tdp_money(t.net_receivable) + '</div></div>';
    html += '</div>';

    // ── Unpaid invoices ─────────────────────────────────────────────
    var invoices = data.invoices || [];
    html += '<div style="font-weight:600;margin:10px 0 6px;">Unpaid Invoices (' + invoices.length + ')</div>';
    if (!invoices.length) {
        html += '<div class="text-muted" style="margin-bottom:10px;">Nothing outstanding for this customer.</div>';
    } else {
        html += '<div style="overflow-x:auto;"><table class="table table-bordered table-condensed" style="font-size:12px;"><thead><tr>'
            + '<th>Invoice</th><th>Date</th><th>Due</th><th class="text-right">Total</th>'
            + '<th class="text-right">Paid</th><th class="text-right">Outstanding</th><th class="text-right">Age</th>'
            + '</tr></thead><tbody>';
        invoices.forEach(function (r) {
            var overdue = Number(r.days_overdue || 0) > 0;
            html += '<tr>'
                + '<td><a href="/app/sales-invoice/' + encodeURIComponent(r.sales_invoice) + '">' + esc(r.sales_invoice) + '</a></td>'
                + '<td>' + esc(r.posting_date) + '</td>'
                + '<td' + (overdue ? ' style="color:#c0392b;font-weight:600;"' : '') + '>' + esc(r.due_date)
                + (overdue ? ' (+' + r.days_overdue + 'd)' : '') + '</td>'
                + '<td class="text-right">' + tdp_money(r.grand_total) + '</td>'
                + '<td class="text-right">' + tdp_money(r.paid_amount) + '</td>'
                + '<td class="text-right" style="font-weight:600;">' + tdp_money(r.outstanding_amount) + '</td>'
                + '<td class="text-right">' + (r.age_days || 0) + 'd</td>'
                + '</tr>';
        });
        html += '</tbody></table></div>';
    }

    // ── Unallocated advances ────────────────────────────────────────
    var advances = data.advances || [];
    if (advances.length) {
        html += '<div style="font-weight:600;margin:12px 0 6px;">Unallocated Advances (' + advances.length + ')</div>';
        html += '<div style="overflow-x:auto;"><table class="table table-bordered table-condensed" style="font-size:12px;"><thead><tr>'
            + '<th>Payment Entry</th><th>Date</th><th>Method</th><th>Reference</th><th class="text-right">Credit</th>'
            + '</tr></thead><tbody>';
        advances.forEach(function (r) {
            html += '<tr>'
                + '<td><a href="/app/payment-entry/' + encodeURIComponent(r.payment_entry) + '">' + esc(r.payment_entry) + '</a></td>'
                + '<td>' + esc(r.posting_date) + '</td>'
                + '<td>' + esc(r.method || "") + '</td>'
                + '<td>' + esc(r.reference || "") + '</td>'
                + '<td class="text-right" style="font-weight:600;">' + tdp_money(r.unallocated_amount) + '</td>'
                + '</tr>';
        });
        html += '</tbody></table></div>';
    }

    // ── Payment history ─────────────────────────────────────────────
    var payments = data.payments || [];
    html += '<div style="font-weight:600;margin:12px 0 6px;">Payment History (' + payments.length + ')</div>';
    if (!payments.length) {
        html += '<div class="text-muted">No payments recorded for this customer yet.</div>';
    } else {
        html += '<div style="overflow-x:auto;"><table class="table table-bordered table-condensed" style="font-size:12px;"><thead><tr>'
            + '<th>Payment Entry</th><th>Date</th><th class="text-right">Amount</th><th>Method</th>'
            + '<th>Reference</th><th>Applied To</th>'
            + '</tr></thead><tbody>';
        payments.forEach(function (r) {
            var against = (r.against || []).map(function (a) {
                return esc(a.sales_invoice) + " (" + tdp_money(a.allocated_amount) + ")";
            }).join("<br>");
            if (!against) {
                against = '<span class="text-muted">unallocated</span>';
            }
            html += '<tr>'
                + '<td><a href="/app/payment-entry/' + encodeURIComponent(r.payment_entry) + '">' + esc(r.payment_entry) + '</a></td>'
                + '<td>' + esc(r.posting_date) + '</td>'
                + '<td class="text-right" style="font-weight:600;">' + tdp_money(r.amount) + '</td>'
                + '<td>' + esc(r.method || "") + '</td>'
                + '<td>' + esc(r.reference || "") + '</td>'
                + '<td>' + against + '</td>'
                + '</tr>';
        });
        html += '</tbody></table></div>';
    }

    html += '<div class="text-muted" style="margin-top:10px;font-size:11px;">'
        + 'Read live from submitted Sales Invoices and Payment Entries. Not stored on this task, so it cannot go out of date. '
        + 'To correct a figure, correct the invoice or payment.</div>';

    wrapper.$wrapper.html(html);
}

function tdp_refresh(frm) {
    if (!frm || !frm.doc) return;
    if (TDP_KINDS.indexOf((frm.doc.task_kind || "").trim()) === -1) return;
    if (!frm.fields_dict.custom_debt_panel) return;
    if (frm.is_new()) return;

    frm.fields_dict.custom_debt_panel.$wrapper.html('<div class="text-muted" style="padding:8px 0;">Loading debt position...</div>');

    frappe.call({
        method: "task_debt_panel",
        args: { task_name: frm.doc.name },
        callback: function (r) {
            var data = r && r.message ? r.message : null;
            console.log("[DebtPanel] task=" + frm.doc.name
                + " customer=" + (data && data.customer ? data.customer : "(none)")
                + " invoices=" + (data && data.invoices ? data.invoices.length : 0));
            tdp_render(frm, data);
        },
        error: function () {
            frm.fields_dict.custom_debt_panel.$wrapper.html(
                '<div style="color:#c0392b;padding:8px 0;">Could not load the debt position. Reload the page to try again.</div>');
        }
    });
}

frappe.ui.form.on("Task", {
    refresh: function (frm) { tdp_refresh(frm); },
    task_kind: function (frm) { tdp_refresh(frm); },
    customer: function (frm) { tdp_refresh(frm); }
});
