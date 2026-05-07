let is_merging = false;
let clearing_initial_barcode = {};

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
    }, 700);
}

function close_item_modal_and_focus_main(frm) {
    $('.modal:visible').modal('hide');
    $('body').removeClass('modal-open');
    $('.modal-backdrop').remove();
    setTimeout(() => focus_main_scan(frm), 300);
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

function close_row_and_focus_main(frm, cdn) {
    let grid_row = frm.fields_dict.items.grid.get_row(cdn);
    if (grid_row) grid_row.toggle_view(false);

    $('.modal:visible').modal('hide');
    $('body').removeClass('modal-open');
    $('.modal-backdrop').remove();

    setTimeout(() => focus_main_scan(frm), 400);
}

frappe.ui.form.on('Purchase Receipt Item', {
    qty: function(frm, cdt, cdn) {
        let row = locals[cdt][cdn];

        if (is_merging || !row) return;

        console.log('=== QTY HANDLER ===');
        console.log('Row:', cdn, 'Qty:', row.qty, 'Batch:', row.batch_no, 'Item:', row.item_code);
        console.log('is_merging:', is_merging);

        if (row.qty > 1 && !row.batch_no) {
            console.log('SPLITTING: qty > 1 and no batch');
            is_merging = true;
            frappe.model.set_value(cdt, cdn, 'qty', row.qty - 1);

            let new_row = frm.add_child('items', {
                item_code: row.item_code,
                item_name: row.item_name,
                description: row.description,
                qty: 1,
                uom: row.uom,
                stock_uom: row.stock_uom,
                conversion_factor: row.conversion_factor,
                warehouse: row.warehouse,
                rate: row.rate
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
                clearing_initial_barcode[cdn] = true;
                frappe.model.set_value(cdt, cdn, 'barcode', '');
                focus_row_barcode(frm, cdn);
            }, 300);
        }
    },

    barcode: function(frm, cdt, cdn) {
        let row = locals[cdt][cdn];
        let current_cdn = cdn;

        if (!row || !row.barcode) return;

        if (clearing_initial_barcode[cdn]) {
            delete clearing_initial_barcode[cdn];
            if (!row.barcode.startsWith(']C111')) {
                frappe.model.set_value(cdt, cdn, 'barcode', '');
                focus_row_barcode(frm, cdn);
                return;
            }
        }

        let raw = row.barcode;
        let parsed = parse_gs1_barcode(raw);

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

        frappe.model.set_value(cdt, cdn, 'batch_no', parsed.lot_number);
        frappe.model.set_value(cdt, cdn, 'custom_expiry_date', parsed.expiry_date);
        frappe.model.set_value(cdt, cdn, 'barcode', '');

        setTimeout(() => {
            row = locals[cdt][cdn];

            console.log('=== MERGE CHECK DEBUG ===');
            console.log('Current row:', current_cdn);
            console.log('Looking for - item:', row.item_code, 'batch:', parsed.lot_number, 'expiry:', parsed.expiry_date);
            console.log('All items:', (frm.doc.items || []).map(i => ({
                name: i.name,
                item_code: i.item_code,
                batch_no: i.batch_no,
                custom_expiry_date: i.custom_expiry_date,
                qty: i.qty
            })));

            let match = (frm.doc.items || []).find(i => {
                if (i.name === current_cdn) return false;
                
                let i_batch = (i.batch_no || '').toString().trim();
                let i_expiry = (i.custom_expiry_date || '').toString().trim();
                let i_item = (i.item_code || '').toString().trim();
                
                let parsed_batch = (parsed.lot_number || '').toString().trim();
                let parsed_expiry = (parsed.expiry_date || '').toString().trim();
                let row_item = (row.item_code || '').toString().trim();
                
                console.log('Checking item:', i.name, 'item match:', i_item === row_item, 'batch match:', i_batch === parsed_batch, 'expiry match:', i_expiry === parsed_expiry);
                
                return i_item === row_item && i_batch === parsed_batch && i_expiry === parsed_expiry;
            });

            console.log('Match found:', match ? match.name : 'NONE');
            console.log('=== END DEBUG ===');

            if (match) {
                frappe.model.set_value(match.doctype, match.name, 'qty', (match.qty || 0) + 1);

                setTimeout(() => {
                    let grid_row = frm.get_field('items').grid.grid_rows_by_docname[current_cdn];
                    if (grid_row) grid_row.remove();
                    frm.refresh_field('items');
                    is_merging = false;
                    close_row_and_focus_main(frm, current_cdn);
                }, 200);
            } else {
                is_merging = false;
                frm.refresh_field('items');
                close_row_and_focus_main(frm, current_cdn);
            }
        }, 500);
    }
});
