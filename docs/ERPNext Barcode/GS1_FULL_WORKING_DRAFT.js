let gs1_is_merging = false;
let gs1_last_row_count = 0;
let gs1_pending_row_focus = null;

const GS1_CONFIG = {
    main_scan_field: 'scan_barcode',
    items_table_field: 'items',
    row_barcode_field: 'barcode',
    batch_field: 'batch_no',
    expiry_field: 'custom_expiry_date',
    manufacturing_field: 'custom_production_date',
    raw_gs1_barcode_field: 'custom_scanned_gs1_barcode',
    item_requires_second_scan_field: 'custom_requires_gs1_lot_scan',
    allow_expired_override_field: 'custom_allow_expired_barcode_receipt',
    allow_future_production_override_field: 'custom_allow_future_production_date',
    override_reason_field: 'custom_barcode_override_reason',
    expiry_notice_days: 180,
    expiry_warning_days: 90,
    non_expiry_item_groups: [],
    gs1_prefixes: [']C1', ']d2'],
    focus_delay_ms: 250,
    popup_focus_delay_ms: 450
};

function gs1_play_error_beep() {
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

function gs1_play_success_beep() {
    if (!(window.AudioContext || window.webkitAudioContext)) return;
    let audioContext = new (window.AudioContext || window.webkitAudioContext)();
    let oscillator = audioContext.createOscillator();
    let gainNode = audioContext.createGain();
    oscillator.connect(gainNode);
    gainNode.connect(audioContext.destination);
    oscillator.frequency.value = 900;
    oscillator.type = 'sine';
    gainNode.gain.value = 0.2;
    oscillator.start(audioContext.currentTime);
    oscillator.stop(audioContext.currentTime + 0.12);
}

function gs1_show_error(message) {
    frappe.show_alert({ message: __(message), indicator: 'red' }, 5);
    gs1_play_error_beep();
}

function gs1_show_success(message) {
    frappe.show_alert({ message: __(message), indicator: 'green' }, 3);
    gs1_play_success_beep();
}

function gs1_is_gs1_barcode(raw) {
    raw = (raw || '').toString();
    return GS1_CONFIG.gs1_prefixes.some(prefix => raw.startsWith(prefix));
}

function gs1_is_ref_barcode(raw) {
    raw = (raw || '').toString().trim();
    return raw.startsWith(']C101');
}

function gs1_is_second_barcode(raw) {
    raw = (raw || '').toString().trim();
    return raw.startsWith(']C111');
}

function gs1_strip_symbology(raw) {
    raw = (raw || '').toString().trim();
    if (raw.startsWith(']C1') || raw.startsWith(']d2')) return raw.substring(3);
    return raw;
}

function gs1_normalize_date(yymmdd) {
    if (!/^\d{6}$/.test(yymmdd || '')) return null;
    let yy = parseInt(yymmdd.substring(0, 2), 10);
    let mm = yymmdd.substring(2, 4);
    let dd = yymmdd.substring(4, 6);
    let yyyy = yy >= 50 ? `19${yymmdd.substring(0, 2)}` : `20${yymmdd.substring(0, 2)}`;
    if (dd === '00') dd = '01';
    if (parseInt(mm, 10) < 1 || parseInt(mm, 10) > 12) return null;
    if (parseInt(dd, 10) < 1 || parseInt(dd, 10) > 31) return null;
    return `${yyyy}-${mm}-${dd}`;
}

function gs1_read_variable_value(data, start, known_ai) {
    let value = '';
    let i = start;
    while (i < data.length) {
        let ch = data.charAt(i);
        if (ch === String.fromCharCode(29)) break;
        let next2 = data.substring(i, i + 2);
        let next3 = data.substring(i, i + 3);
        let next4 = data.substring(i, i + 4);
        if (value.length > 0 && (known_ai[next2] || known_ai[next3] || known_ai[next4])) break;
        value += ch;
        i += 1;
    }
    return { value: value, next: i };
}

function gs1_parse_barcode(raw) {
    if (!gs1_is_gs1_barcode(raw)) return null;

    let data = gs1_strip_symbology(raw);
    let known_ai = {
        '01': { name: 'gtin', len: 14 },
        '10': { name: 'lot_number', variable: true },
        '11': { name: 'manufacturing_date', len: 6, date: true },
        '17': { name: 'expiry_date', len: 6, date: true },
        '21': { name: 'serial_number', variable: true },
        '240': { name: 'additional_item_id', variable: true },
        '241': { name: 'customer_part_number', variable: true }
    };

    let result = {};
    let i = 0;

    while (i < data.length) {
        if (data.charAt(i) === String.fromCharCode(29)) {
            i += 1;
            continue;
        }

        let ai = null;
        let def = null;
        [4, 3, 2].some(len => {
            let candidate = data.substring(i, i + len);
            if (known_ai[candidate]) {
                ai = candidate;
                def = known_ai[candidate];
                return true;
            }
            return false;
        });

        if (!ai || !def) {
            i += 1;
            continue;
        }

        i += ai.length;

        if (def.variable) {
            let read = gs1_read_variable_value(data, i, known_ai);
            result[def.name] = read.value;
            i = read.next;
        } else {
            let value = data.substring(i, i + def.len);
            result[def.name] = def.date ? gs1_normalize_date(value) : value;
            i += def.len;
        }
    }

    if (!result.lot_number && data.indexOf('10') >= 0) {
        let fallback_lot = data.substring(data.indexOf('10') + 2).trim();
        if (fallback_lot) result.lot_number = fallback_lot;
    }

    if (!result.expiry_date && data.length >= 19) {
        result.expiry_date = gs1_normalize_date(data.substring(10, 16)) || gs1_normalize_date(data.substring(13, 19));
    }

    if (!result.lot_number) return null;
    return result;
}

function gs1_focus_main_scan(frm) {
    setTimeout(() => {
        frm.set_value(GS1_CONFIG.main_scan_field, '');
        let field = frm.get_field(GS1_CONFIG.main_scan_field);
        if (field && field.$input) {
            field.$input.val('').focus();
            setTimeout(() => field.$input.focus(), 100);
            return;
        }
        let input = $(`[data-fieldname="${GS1_CONFIG.main_scan_field}"]:visible input:visible`).first();
        if (input.length) {
            input.val('').focus();
            setTimeout(() => input.focus(), 100);
        }
    }, GS1_CONFIG.focus_delay_ms);
}

function gs1_get_grid(frm) {
    return frm.fields_dict[GS1_CONFIG.items_table_field].grid;
}

function gs1_get_grid_row(frm, cdn) {
    let grid = gs1_get_grid(frm);
    return grid.grid_rows_by_docname ? grid.grid_rows_by_docname[cdn] : grid.get_row(cdn);
}

function gs1_open_row_and_focus_barcode(frm, cdn) {
    setTimeout(() => {
        let grid_row = gs1_get_grid_row(frm, cdn) || gs1_get_grid(frm).get_row(cdn);
        if (!grid_row) return;
        grid_row.toggle_view(true);
        setTimeout(() => {
            let field = grid_row.grid_form && grid_row.grid_form.fields_dict[GS1_CONFIG.row_barcode_field];
            if (field && field.$input) {
                field.$input.val('').focus();
                setTimeout(() => field.$input.focus(), 100);
                return;
            }
            let input = $(`.modal:visible [data-fieldname="${GS1_CONFIG.row_barcode_field}"] input:visible`).first();
            if (input.length) input.val('').focus();
        }, GS1_CONFIG.popup_focus_delay_ms);
    }, 200);
}

function gs1_close_row_popup(frm, cdn) {
    let grid_row = gs1_get_grid_row(frm, cdn) || gs1_get_grid(frm).get_row(cdn);
    if (grid_row) grid_row.toggle_view(false);
    $('.modal:visible').modal('hide');
    $('body').removeClass('modal-open');
    $('.modal-backdrop').remove();
}

function gs1_remove_child_row(frm, cdn) {
    let grid_row = gs1_get_grid_row(frm, cdn);
    if (grid_row && grid_row.remove) {
        grid_row.remove();
    } else {
        frm.doc[GS1_CONFIG.items_table_field] = (frm.doc[GS1_CONFIG.items_table_field] || []).filter(row => row.name !== cdn);
    }
    frm.refresh_field(GS1_CONFIG.items_table_field);
}

function gs1_get_latest_item_row(frm) {
    let rows = frm.doc[GS1_CONFIG.items_table_field] || [];
    return rows.length ? rows[rows.length - 1] : null;
}

function gs1_is_blank_identity_row(row) {
    return row && row.item_code && !row[GS1_CONFIG.batch_field] && !row[GS1_CONFIG.expiry_field];
}

function gs1_fetch_item_scan_policy(item_code) {
    return new Promise(resolve => {
        if (!item_code) {
            resolve({ requires_second_scan: true });
            return;
        }

        frappe.db.get_value('Item', item_code, [
            'item_code',
            'item_group',
            'has_batch_no',
            'has_expiry_date',
            'has_serial_no',
            GS1_CONFIG.item_requires_second_scan_field
        ]).then(r => {
            let item = (r && r.message) || {};
            let explicit = item[GS1_CONFIG.item_requires_second_scan_field];
            let in_non_expiry_group = GS1_CONFIG.non_expiry_item_groups.includes(item.item_group);
            let requires_second_scan;

            if (explicit === 1 || explicit === true || explicit === '1' || explicit === 'Yes') {
                requires_second_scan = true;
            } else if (explicit === 0 || explicit === false || explicit === '0' || explicit === 'No') {
                requires_second_scan = false;
            } else if (in_non_expiry_group) {
                requires_second_scan = false;
            } else {
                requires_second_scan = !!(item.has_batch_no || item.has_expiry_date || item.has_serial_no);
            }

            resolve({ item: item, requires_second_scan: requires_second_scan });
        }).catch(() => {
            resolve({ requires_second_scan: true });
        });
    });
}

function gs1_find_duplicate_row(frm, current_cdn, row, parsed) {
    let current_item = (row.item_code || '').toString().trim();
    let current_batch = (parsed.lot_number || '').toString().trim();
    let current_expiry = (parsed.expiry_date || '').toString().trim();

    return (frm.doc[GS1_CONFIG.items_table_field] || []).find(candidate => {
        if (candidate.name === current_cdn) return false;
        let item_matches = (candidate.item_code || '').toString().trim() === current_item;
        let batch_matches = (candidate[GS1_CONFIG.batch_field] || '').toString().trim() === current_batch;
        let expiry_matches = (candidate[GS1_CONFIG.expiry_field] || '').toString().trim() === current_expiry;
        return item_matches && batch_matches && expiry_matches;
    });
}

function gs1_date_to_local_midnight(value) {
    if (!value) return null;
    let parts = value.split('-').map(part => parseInt(part, 10));
    if (parts.length !== 3 || parts.some(isNaN)) return null;
    return new Date(parts[0], parts[1] - 1, parts[2]);
}

function gs1_validate_dates(frm, parsed) {
    let today = new Date();
    today = new Date(today.getFullYear(), today.getMonth(), today.getDate());
    let expiry = gs1_date_to_local_midnight(parsed.expiry_date);
    let production = gs1_date_to_local_midnight(parsed.manufacturing_date);

    if (expiry && expiry < today && !frm.doc[GS1_CONFIG.allow_expired_override_field]) {
        return {
            valid: false,
            message: 'This product is expired. Enable the expired-item override field only if management approves this exception.'
        };
    }

    if (expiry && expiry < today && frm.doc[GS1_CONFIG.allow_expired_override_field] && !frm.doc[GS1_CONFIG.override_reason_field]) {
        return {
            valid: false,
            message: 'Please enter a barcode override reason before receiving expired product.'
        };
    }

    if (production && production > today && !frm.doc[GS1_CONFIG.allow_future_production_override_field]) {
        return {
            valid: false,
            message: 'Production date is in the future. Enable the future-production-date override only if this is an approved exception.'
        };
    }

    if (production && production > today && frm.doc[GS1_CONFIG.allow_future_production_override_field] && !frm.doc[GS1_CONFIG.override_reason_field]) {
        return {
            valid: false,
            message: 'Please enter a barcode override reason before receiving product with future production date.'
        };
    }

    if (expiry && production && expiry <= production) {
        return {
            valid: false,
            message: 'Expiry date must be after production date.'
        };
    }

    if (expiry) {
        let days_left = Math.ceil((expiry.getTime() - today.getTime()) / 86400000);
        if (days_left >= 0 && days_left <= GS1_CONFIG.expiry_warning_days) {
            return {
                valid: true,
                warning: `Strong warning: this product expires in ${days_left} days. Please confirm it is acceptable before submitting.`
            };
        }
        if (days_left > GS1_CONFIG.expiry_warning_days && days_left <= GS1_CONFIG.expiry_notice_days) {
            return {
                valid: true,
                warning: `Notice: this product expires in ${days_left} days.`
            };
        }
    }

    return { valid: true };
}

function gs1_after_row_finalized(frm, cdn) {
    gs1_close_row_popup(frm, cdn);
    gs1_focus_main_scan(frm);
}

frappe.ui.form.on('Purchase Receipt', {
    refresh: function(frm) {
        gs1_last_row_count = (frm.doc[GS1_CONFIG.items_table_field] || []).length;
        gs1_focus_main_scan(frm);
    },

    scan_barcode: function(frm) {
        let scanned_value = (frm.doc[GS1_CONFIG.main_scan_field] || '').toString().trim();
        if (!scanned_value) return;

        if (gs1_is_second_barcode(scanned_value)) {
            gs1_show_error('Wrong barcode. Please scan the REF barcode first.');
            gs1_focus_main_scan(frm);
            return;
        }

        gs1_last_row_count = (frm.doc[GS1_CONFIG.items_table_field] || []).length;
        gs1_pending_row_focus = { started_at: Date.now(), scan: scanned_value };
    }
});

frappe.ui.form.on('Purchase Receipt Item', {
    item_code: function(frm, cdt, cdn) {
        let row = locals[cdt][cdn];
        if (!row || !row.item_code || gs1_is_merging) return;

        gs1_fetch_item_scan_policy(row.item_code).then(policy => {
            row = locals[cdt][cdn];
            if (!row || !row.item_code) return;

            if (policy.requires_second_scan) {
                if (gs1_is_blank_identity_row(row)) {
                    frappe.model.set_value(cdt, cdn, GS1_CONFIG.row_barcode_field, '');
                    gs1_open_row_and_focus_barcode(frm, cdn);
                }
            } else {
                gs1_open_row_and_focus_barcode(frm, cdn);
                frappe.show_alert({
                    message: __('Non-expiry item. Enter quantity, then save/close the row.'),
                    indicator: 'blue'
                }, 4);
            }
        });
    },

    qty: function(frm, cdt, cdn) {
        let row = locals[cdt][cdn];
        if (gs1_is_merging || !row || !row.item_code) return;

        gs1_fetch_item_scan_policy(row.item_code).then(policy => {
            row = locals[cdt][cdn];
            if (!row) return;

            if (!policy.requires_second_scan) {
                gs1_close_row_popup(frm, cdn);
                gs1_focus_main_scan(frm);
                return;
            }

            if (row.qty > 1 && !row[GS1_CONFIG.batch_field]) {
                gs1_is_merging = true;
                frappe.model.set_value(cdt, cdn, 'qty', row.qty - 1).then(() => {
                    let new_row = frm.add_child(GS1_CONFIG.items_table_field, {
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
                    frm.refresh_field(GS1_CONFIG.items_table_field);
                    gs1_is_merging = false;
                    frappe.model.set_value(new_row.doctype, new_row.name, GS1_CONFIG.row_barcode_field, '');
                    gs1_open_row_and_focus_barcode(frm, new_row.name);
                });
                return;
            }

            if (gs1_is_blank_identity_row(row)) {
                frappe.model.set_value(cdt, cdn, GS1_CONFIG.row_barcode_field, '');
                gs1_open_row_and_focus_barcode(frm, cdn);
            }
        });
    },

    [GS1_CONFIG.row_barcode_field]: function(frm, cdt, cdn) {
        let row = locals[cdt][cdn];
        if (!row) return;

        let raw = (row[GS1_CONFIG.row_barcode_field] || '').toString().trim();
        if (!raw) return;

        let parsed = gs1_parse_barcode(raw);
        if (!parsed) {
            gs1_show_error('Wrong barcode. Please scan the second barcode with LOT and expiry data.');
            frappe.model.set_value(cdt, cdn, GS1_CONFIG.row_barcode_field, '');
            gs1_open_row_and_focus_barcode(frm, cdn);
            return;
        }

        let date_validation = gs1_validate_dates(frm, parsed);
        if (!date_validation.valid) {
            gs1_show_error(date_validation.message);
            frappe.model.set_value(cdt, cdn, GS1_CONFIG.row_barcode_field, '');
            gs1_open_row_and_focus_barcode(frm, cdn);
            return;
        }

        gs1_is_merging = true;

        let values = {};
        values[GS1_CONFIG.batch_field] = parsed.lot_number;
        values[GS1_CONFIG.expiry_field] = parsed.expiry_date || '';
        values[GS1_CONFIG.row_barcode_field] = '';
        if (GS1_CONFIG.raw_gs1_barcode_field) {
            values[GS1_CONFIG.raw_gs1_barcode_field] = raw;
        }
        if (GS1_CONFIG.manufacturing_field && parsed.manufacturing_date) {
            values[GS1_CONFIG.manufacturing_field] = parsed.manufacturing_date;
        }

        frappe.model.set_value(cdt, cdn, values).then(() => {
            row = locals[cdt][cdn];
            let match = gs1_find_duplicate_row(frm, cdn, row, parsed);

            if (match) {
                frappe.model.set_value(match.doctype, match.name, 'qty', (match.qty || 0) + 1).then(() => {
                    gs1_remove_child_row(frm, cdn);
                    gs1_is_merging = false;
                    gs1_show_success('Barcode accepted. Quantity merged.');
                    if (date_validation.warning) frappe.show_alert({ message: __(date_validation.warning), indicator: 'orange' }, 7);
                    gs1_after_row_finalized(frm, cdn);
                });
            } else {
                gs1_is_merging = false;
                frm.refresh_field(GS1_CONFIG.items_table_field);
                gs1_show_success('Barcode accepted.');
                if (date_validation.warning) frappe.show_alert({ message: __(date_validation.warning), indicator: 'orange' }, 7);
                gs1_after_row_finalized(frm, cdn);
            }
        }).catch(() => {
            gs1_is_merging = false;
            gs1_show_error('Could not write barcode data to the row. Please try again.');
            frappe.model.set_value(cdt, cdn, GS1_CONFIG.row_barcode_field, '');
            gs1_open_row_and_focus_barcode(frm, cdn);
        });
    }
});
