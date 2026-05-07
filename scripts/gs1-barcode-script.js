frappe.ui.form.on('Purchase Receipt Item', {
    qty: function(frm, cdt, cdn) {
        // Guard: skip split logic if we are in the middle of a merge
        if (frm._merging) return;

        let row = locals[cdt][cdn];

        // 1. THE SPLIT: If a second scan hits the same row, force it into a new one
        if (row.qty > 1) {
            frappe.model.set_value(cdt, cdn, 'qty', 1);

            let new_row = frm.add_child('items', {
                item_code: row.item_code,
                qty: 1
            });
            frm.refresh_field('items');

            // Re-target the logic to the brand-new row
            cdn = new_row.name;
            row = locals[cdt][cdn];
        }

        // 2. THE POP-UP: Only open if the row is fresh (no Batch/LOT yet)
        if (row.item_code && !row.batch_no) {
            // Small delay to let ERPNext finish its background calculations
            setTimeout(() => {
                // Check again to make sure another script hasn't filled the batch
                if (!row.batch_no) {
                    frm.fields_dict.items.grid.get_row(cdn).toggle_view(true);

                    setTimeout(() => {
                        let $inp = $('[data-fieldname="barcode"]').find('input');
                        if ($inp.length) {
                            $inp.val('').focus();
                        }
                    }, 500);
                }
            }, 150);
        }
    },

    barcode: function(frm, cdt, cdn) {
        let row = locals[cdt][cdn];

        // Process ONLY the 2D Medical Barcode
        if (row.barcode && row.barcode.startsWith(']C111')) {
            let raw = row.barcode;
            let expiry_date = `20${raw.substring(13,15)}-${raw.substring(15,17)}-${raw.substring(17,19)}`;
            let lot_number = raw.substring(raw.indexOf('10', 19) + 2);

            // Set values and clear temp barcode field
            frappe.model.set_value(cdt, cdn, {
                'batch_no': lot_number,
                'custom_expiry_date': expiry_date,
                'barcode': ''
            });

            // 3. SMART MERGE: Check for identical Item + LOT + Expiry
            let match = (frm.doc.items || []).find(i =>
                i.name !== cdn && i.item_code === row.item_code &&
                i.batch_no === lot_number && i.custom_expiry_date === expiry_date
            );

            if (match) {
                // Set flag BEFORE incrementing qty so the qty trigger
                // does not split the matched row during the merge
                frm._merging = true;
                frappe.model.set_value(match.doctype, match.name, 'qty', (match.qty || 0) + 1);
                frm._merging = false;
                frm.get_field('items').grid.grid_rows_by_name[cdn].remove();
            }

            // 4. UI CLEANUP: Close pop-up and refocus the main scanner
            setTimeout(() => {
                $('.modal:visible').modal('hide');
                $('body').removeClass('modal-open');
                $('.modal-backdrop').remove();

                let grid_row = frm.fields_dict.items.grid.get_row(cdn);
                if (grid_row) grid_row.toggle_view(false);

                setTimeout(() => {
                    let main_scan = $('[data-fieldname="scan_barcode"] input');
                    if (main_scan.length) {
                        main_scan.focus().val('');
                    }
                }, 700);
            }, 200);
        }
    }
});
