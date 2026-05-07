let is_merging = false;

function play_error_beep() {
    if (!(window.AudioContext || window.webkitAudioContext)) return;

    let audioContext = new (window.AudioContext || window.webkitAudioContext)();
    let oscillator = audioContext.createOscillator();
    let gainNode = audioContext.createGain();

    oscillator.connect(gainNode);
    gainNode.connect(audioContext.destination);

    oscillator.frequency.value = 400;
    oscillator.type = 'sine';
    gainNode.gain.value = 0.3;

    oscillator.start(audioContext.currentTime);
    oscillator.stop(audioContext.currentTime + 0.2);
}

function focus_main_scan(frm) {
    setTimeout(() => {
        let field = frm.get_field('scan_barcode');
        if (field && field.$input) {
            field.$input.val('').focus();
            setTimeout(() => field.$input.focus(), 100);
            return;
        }

        let main_scan = $('[data-fieldname="scan_barcode"]:visible').find('input:visible').first();
        if (main_scan.length) {
            main_scan.val('').focus();
            setTimeout(() => main_scan.focus(), 100);
        }
    }, 200);
}

function focus_row_barcode(frm, cdn) {
    setTimeout(() => {
        let grid_row = frm.fields_dict.items.grid.get_row(cdn);
        if (grid_row && grid_row.grid_form && grid_row.grid_form.fields_dict.barcode) {
            let field = grid_row.grid_form.fields_dict.barcode;
            if (field.$input) {
                field.$input.val('').focus();
                return;
            }
        }

        let barcode_input = $('.modal:visible [data-fieldname="barcode"] input:visible').first();
        if (barcode_input.length) barcode_input.val('').focus();
    }, 300);
}

function parse_gs1_barcode(raw) {
    if (!raw || !raw.startsWith(']C111')) return null;

    let expiry_date = `20${raw.substring(13, 15)}-${raw.substring(15, 17)}-${raw.substring(17, 19)}`;
    let lot_ai_index = raw.indexOf('10', 19);

    if (lot_ai_index === -1) return null;

    let lot_number = raw.substring(lot_ai_index + 2);

    if (!lot_number) return null;

    return {
        expiry_date: expiry_date,
        lot_number: lot_number
    };
}

frappe.ui.form.on('Purchase Receipt Item', {
    qty: function(frm, cdt, cdn) {
        let row = locals[cdt][cdn];

        if (is_merging || !row) return;

        if (row.qty > 1) {
            is_merging = true;
            frappe.model.set_value(cdt, cdn, 'qty', 1);

            let new_row = frm.add_child('items', {
                item_code: row.item_code,
                qty: 1
            });
            frm.refresh_field('items');

            cdn = new_row.name;
            row = locals[cdt][cdn];
            is_merging = false;
        }

        if (row.item_code && !row.batch_no && !is_merging) {
            setTimeout(() => {
                row = locals[cdt][cdn];
                if (!row || row.batch_no) return;

                let grid_row = frm.fields_dict.items.grid.get_row(cdn);
                if (!grid_row) return;

                grid_row.toggle_view(true);
                focus_row_barcode(frm, cdn);
            }, 300);
        }
    },

    barcode: function(frm, cdt, cdn) {
        let row = locals[cdt][cdn];
        let current_cdn = cdn;

        if (!row || !row.barcode) return;

        let parsed = parse_gs1_barcode(row.barcode);

        if (!parsed) {
            frappe.show_alert({
                message: __('Invalid barcode. Please scan the GS1 LOT barcode, not the REF barcode.'),
                indicator: 'red'
            }, 5);

            play_error_beep();
            frappe.model.set_value(cdt, cdn, 'barcode', '');
            focus_row_barcode(frm, cdn);
            return;
        }

        is_merging = true;

        frappe.model.set_value(cdt, cdn, {
            batch_no: parsed.lot_number,
            custom_expiry_date: parsed.expiry_date,
            barcode: ''
        }).then(() => {
            let match = (frm.doc.items || []).find(i =>
                i.name !== current_cdn &&
                i.item_code === row.item_code &&
                i.batch_no === parsed.lot_number &&
                i.custom_expiry_date === parsed.expiry_date
            );

            if (match) {
                frappe.model.set_value(match.doctype, match.name, 'qty', (match.qty || 0) + 1).then(() => {
                    frm.get_field('items').grid.grid_rows_by_docname[current_cdn].remove();
                    frm.refresh_field('items');
                    is_merging = false;
                    focus_main_scan(frm);
                });
            } else {
                is_merging = false;
                frm.refresh_field('items');
                focus_main_scan(frm);
            }

            setTimeout(() => {
                $('.modal:visible').modal('hide');
                $('body').removeClass('modal-open');
                $('.modal-backdrop').remove();
            }, 100);
        });
    }
});
