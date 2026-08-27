// Name: LCV-import-duty-prefill
// DocType: Landed Cost Voucher
// Enabled: 1
// ---

frappe.ui.form.on('Landed Cost Voucher', {
    refresh: function(frm) {
        if (frm.doc.docstatus === 0) {
            frm.add_custom_button(__('Pre-fill Import Duty'), function() {
                prefill_import_duty(frm);
            }, __('Tools'));
        }
    }
});

function prefill_import_duty(frm) {
    var items = frm.doc.items || [];
    if (!items.length) {
        frappe.msgprint(__('No items loaded. Add Purchase Receipts and click "Get Items from Purchase Receipts" first.'));
        return;
    }

    var item_codes = [];
    items.forEach(function(r) { if (r.item_code && item_codes.indexOf(r.item_code) === -1) item_codes.push(r.item_code); });

    frappe.call({
        method: 'frappe.client.get_list',
        args: {
            doctype: 'Item',
            filters: [['item_code', 'in', item_codes]],
            fields: ['item_code', 'import_tax_rate'],
            limit_page_length: 500
        },
        callback: function(r) {
            if (!r.message) return;

            var rate_map = {};
            (r.message || []).forEach(function(row) {
                rate_map[row.item_code] = flt(row.import_tax_rate) || 0;
            });

            var total_duty = 0;
            items.forEach(function(row) {
                var rate = rate_map[row.item_code] || 0;
                total_duty += flt(row.amount) * rate / 100.0;
            });
            total_duty = Math.round(total_duty * 100) / 100;

            if (total_duty <= 0) {
                frappe.msgprint(__('Import duty calculated as 0. Ensure import_tax_rate is set on the Item records in this receipt.'));
                return;
            }

            // Update existing Import Duty row or insert a new one
            var taxes = frm.doc.taxes || [];
            var existing = null;
            for (var i = 0; i < taxes.length; i++) {
                if (taxes[i].description === 'Import Duty') { existing = taxes[i]; break; }
            }

            if (existing) {
                frappe.model.set_value(existing.doctype, existing.name, 'amount', total_duty);
            } else {
                var row = frm.add_child('taxes');
                row.description = 'Import Duty';
                row.amount = total_duty;
            }
            frm.refresh_field('taxes');

            frappe.show_alert({
                message: __('Import Duty pre-filled: {0} AMD. Set Expense Account and confirm before submitting.', [format_number(total_duty)]),
                indicator: 'green'
            }, 8);
        }
    });
}