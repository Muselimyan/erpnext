let is_merging = false;

frappe.ui.form.on('Purchase Receipt', {
    scan_barcode: function(frm, cdt, cdn) {
        let scanned_value = frm.doc.scan_barcode;
        
        if (!scanned_value) return;
        
        if (scanned_value.startsWith(']C111')) {
            frappe.show_alert({
                message: __('Please scan the REF barcode first, not the LOT barcode'),
                indicator: 'red'
            }, 5);
            
            if (window.AudioContext || window.webkitAudioContext) {
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
            
            frappe.model.set_value('Purchase Receipt', frm.doc.name, 'scan_barcode', '');
            
            setTimeout(() => {
                let main_scan = $('[data-fieldname="scan_barcode"]').find('input');
                if (main_scan.length) main_scan.val('').focus();
            }, 100);
            
            return;
        }
        
        frappe.model.set_value('Purchase Receipt', frm.doc.name, 'scan_barcode', '');
        
        setTimeout(() => {
            let main_scan = $('[data-fieldname="scan_barcode"]').find('input');
            if (main_scan.length) main_scan.val('').focus();
        }, 100);
    }
});

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
                if (!row.batch_no) {
                    frm.fields_dict.items.grid.get_row(cdn).toggle_view(true);
                    setTimeout(() => {
                        let $inp = $('[data-fieldname="barcode"]').find('input');
                        if ($inp.length) $inp.val('').focus();
                    }, 500);
                }
            }, 150);
        }
    },

    barcode: function(frm, cdt, cdn) {
        let row = locals[cdt][cdn];
        let current_cdn = cdn;
        
        if (!row.barcode) return;
        
        if (!row.barcode.startsWith(']C111')) {
            frappe.show_alert({
                message: __('Invalid barcode format. Please scan the LOT barcode (should start with ]C111)'),
                indicator: 'red'
            }, 5);
            
            if (window.AudioContext || window.webkitAudioContext) {
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
            
            frappe.model.set_value(cdt, cdn, 'barcode', '');
            
            setTimeout(() => {
                let $inp = $('[data-fieldname="barcode"]').find('input');
                if ($inp.length) $inp.val('').focus();
            }, 100);
            
            return;
        }
        
        if (row.barcode && row.barcode.startsWith(']C111')) {
            let raw = row.barcode;
            let expiry_date = `20${raw.substring(13,15)}-${raw.substring(15,17)}-${raw.substring(17,19)}`;
            let lot_number = raw.substring(raw.indexOf('10', 19) + 2);

            frappe.model.set_value(cdt, cdn, {
                'batch_no': lot_number,
                'custom_expiry_date': expiry_date,
                'barcode': ''
            });

            let match = (frm.doc.items || []).find(i => 
                i.name !== current_cdn && 
                i.item_code === row.item_code && 
                i.batch_no === lot_number && 
                i.custom_expiry_date === expiry_date
            );

            setTimeout(() => {
                $('.modal:visible').modal('hide');
                $('body').removeClass('modal-open');
                $('.modal-backdrop').remove();
                
                let grid_row = frm.fields_dict.items.grid.get_row(current_cdn);
                if (grid_row) grid_row.toggle_view(false);

                setTimeout(() => {
                    if (match) {
                        is_merging = true;
                        
                        let new_qty = (match.qty || 0) + 1;
                        frappe.model.set_value(match.doctype, match.name, 'qty', new_qty);
                        
                        frm.doc.items = frm.doc.items.filter(item => item.name !== current_cdn);
                        frm.fields_dict.items.grid.refresh();
                        
                        is_merging = false;
                    }

                    let main_scan = $('[data-fieldname="scan_barcode"]').find('input');
                    if (main_scan.length) {
                        main_scan.val('').focus();
                        setTimeout(() => main_scan.focus(), 100);
                    }
                }, 450); 
            }, 200);
        }
    }
});

