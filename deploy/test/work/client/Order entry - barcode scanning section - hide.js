// Name: Order entry - barcode scanning section - hide
// DocType: Task
// Enabled: 1
// ---

frappe.ui.form.on('Task', {
    onload: function(frm) {
        clean_task_layouts(frm);
    },
    refresh: function(frm) {
        clean_task_layouts(frm);
        fetch_pack_prepare_photo(frm);
    },
    task_kind: function(frm) {
        clean_task_layouts(frm);
        fetch_pack_prepare_photo(frm);
    }
});

function clean_task_layouts(frm) {
    const taskKind = (frm.doc.task_kind || "").toString().toLowerCase().trim();

    // Standardized Task Identification Conditions
    const isOrderEntry = (taskKind === "order entry" || taskKind === "order accepting");
    const isPackPrepare = (taskKind === "pack / prepare items");
    const isDelivery = (taskKind === "delivery" || taskKind === "delivery task");
    const isReturnCall = (taskKind === "return call");
    const isPickupReturns = (taskKind === "pickup returns");
    const isInspectReturns = (taskKind === "returns processing / verification");
    const isInvoicePrep = (taskKind.includes("invoice preparation") || taskKind.includes("create invoice"));
    const isReturnsRestocking = (taskKind === "returns restocking");
    const isDebtCollection = (taskKind === "debt collection");
    const isDebtClosure = (taskKind === "debt closure approval");

    const barcodeLabels = [
        "Scan Product Barcode", "Choose Product", "Scan Qty", 
        "Product Qty", "Batch / LOT", "Unit Price"
    ];

    if (frm.fields_dict) {
        Object.values(frm.fields_dict).forEach(function(field) {
            if (!field || !field.df) return;

            // --- A. TEAM QUEUE FIELDS VISIBILITY ---
            if (
                field.df.fieldname === "team_queue_task" || field.df.label === "Team Queue Task" ||
                field.df.fieldname === "team_queue_role" || field.df.label === "Team Queue Role" ||
                field.df.fieldname === "team_queue_status" || field.df.label === "Team Queue Status" ||
                field.df.fieldname === "team_notified" || field.df.label === "Team Notified"
            ) {
                frm.toggle_display(field.df.fieldname, !isDebtClosure);
            }

            // --- B. BARCODE / PRODUCT FIELDS VISIBILITY ---
            if (field.df.label && barcodeLabels.includes(field.df.label)) {
                if (isOrderEntry || isDelivery || isReturnCall || isPickupReturns || isInvoicePrep || isReturnsRestocking || isDebtCollection || isDebtClosure) {
                    frm.toggle_display(field.df.fieldname, false);
                } else {
                    frm.toggle_display(field.df.fieldname, true);
                }
            }

            // --- C. PHOTOS VISIBILITY ---
            if (field.df.label === "Warehouse Pickup Photo" || field.df.label === "Warehouse Drop-off Photo") {
                if (isOrderEntry || isReturnCall || isInspectReturns || isInvoicePrep || isReturnsRestocking || isDebtCollection || isDebtClosure) {
                    frm.toggle_display(field.df.fieldname, false);
                } else if (isPickupReturns) {
                    if (field.df.label === "Warehouse Pickup Photo") {
                        frm.toggle_display(field.df.fieldname, false);
                    } else {
                        frm.toggle_display(field.df.fieldname, true);
                    }
                } else if (isPackPrepare || isDelivery) {
                    if (field.df.label === "Warehouse Drop-off Photo") {
                        frm.toggle_display(field.df.fieldname, false);
                    } else {
                        frm.toggle_display(field.df.fieldname, true);
                    }
                } else {
                    frm.toggle_display(field.df.fieldname, true);
                }
            }

            // --- D. CUSTOM DELIVERY PHOTO / CONTAINER RENDERING ---
            if (field.df.label === "Delivery Photo") {
                frm.toggle_display(field.df.fieldname, isInspectReturns);
                frm.set_df_property(field.df.fieldname, 'read_only', 1);
            }

            // --- E. DRIVER HANDOVER NOTE ---
            if (field.df.label === "Driver Handover Note" || field.df.fieldname === "driver_handover_note") {
                frm.toggle_display(field.df.fieldname, false);
            }

            // --- F. PRODUCT LINES CHILD TABLE ---
            if (field.df.label === "Product Lines") {
                if (isPackPrepare || isDelivery || isReturnCall || isPickupReturns || isInspectReturns || isInvoicePrep || isReturnsRestocking || isDebtCollection || isDebtClosure) {
                    frm.toggle_display(field.df.fieldname, false);
                } else {
                    frm.toggle_display(field.df.fieldname, true);
                }
            }

            // --- G. ACTIVITY LOG BLOCK ---
            if (field.df.label === "Activity" || field.df.fieldname === "activity") {
                frm.toggle_display(field.df.fieldname, !isReturnCall);
            }

            // --- H. SECTION HEADER MANAGEMENT & RENAMING ---
            if (field.df.fieldtype === "Section Break" && field.df.label === "Barcode Scanning (Optional)") {
                if (isDebtClosure) {
                    field.set_label("Total amount paid and profit");
                } else if (isDebtCollection) {
                    field.set_label("Debt amount and status");
                } else if (isOrderEntry || isDelivery || isReturnCall || isPickupReturns || isInvoicePrep || isReturnsRestocking) {
                    field.set_label("Task Status & Priority");
                } else {
                    field.set_label("Barcode Scanning (Optional)");
                }
            }
        });
    }

    // --- 2. COLUMN DOM ARRANGEMENT MECHANICS ---
    if (frm.fields_dict) {
        let targetField1 = Object.values(frm.fields_dict).find(f => f.df && f.df.label === "Scan Product Barcode");
        let targetField2 = Object.values(frm.fields_dict).find(f => f.df && f.df.label === "Choose Product");
        let targetField3 = Object.values(frm.fields_dict).find(f => f.df && f.df.label === "Status");

        const layoutSnap = (isOrderEntry || isDelivery || isReturnCall || isPickupReturns || isInvoicePrep || isReturnsRestocking);

        if (targetField1 && targetField1.$wrapper && targetField2 && targetField2.$wrapper && targetField3 && targetField3.$wrapper) {
            let col1 = targetField1.$wrapper.closest('.form-column');
            let col2 = targetField2.$wrapper.closest('.form-column');
            let col3 = targetField3.$wrapper.closest('.form-column');

            if (col1.length && col2.length && col3.length) {
                if (isDebtClosure) {
                    col1.show().css({ "display": "block", "flex": "", "max-width": "" });
                    col2.show().css({ "display": "block", "flex": "", "max-width": "" });
                    col3.show().css({ "display": "block", "flex": "", "max-width": "" });

                    let profitField = Object.values(frm.fields_dict).find(f => f.df && f.df.label === "Case Profit");
                    let paidField = Object.values(frm.fields_dict).find(f => f.df && f.df.label === "Total Amount Paid");
                    let statusField = Object.values(frm.fields_dict).find(f => f.df && f.df.label === "Status");
                    let priorityField = Object.values(frm.fields_dict).find(f => f.df && f.df.label === "Priority");

                    if (profitField && profitField.$wrapper) col1.append(profitField.$wrapper);
                    if (paidField && paidField.$wrapper) col1.append(paidField.$wrapper);
                    if (statusField && statusField.$wrapper) col2.append(statusField.$wrapper);
                    if (priorityField && priorityField.$wrapper) col2.append(priorityField.$wrapper);

                } else if (isDebtCollection) {
                    col1.hide();
                    col3.show();
                    col2.show().css({ "display": "", "flex": "0 0 66.666%", "max-width": "66.666%" });
                } else {
                    col1.css({ "display": "" });
                    col2.css({ "display": "", "flex": "", "max-width": "" });
                    col3.css({ "display": "" }).show();
                    layoutSnap ? col1.hide() : col1.show();
                    layoutSnap ? col2.hide() : col2.show();
                }
            }
        }
    }
}

// --- 3. FETCH PACK/PREPARE PHOTO DATA LINK & GALLERY ---
function fetch_pack_prepare_photo(frm) {
    const taskKind = (frm.doc.task_kind || "").toString().toLowerCase().trim();
    const isInspectReturns = (taskKind === "returns processing / verification");

    if (!isInspectReturns || !frm.doc.dispatch_case) return;

    // Find the Pack task for this dispatch case
    frappe.call({
        method: 'frappe.client.get_list',
        args: {
            doctype: 'Task',
            filters: { dispatch_case: frm.doc.dispatch_case, task_kind: 'Pack / prepare items' },
            fields: ['name', 'warehouse_pickup_photo'],
            limit_page_length: 1
        },
        async: true,
        callback: function(r) {
            if (!r || !r.message || !r.message.length) return;
            var packTask = r.message[0];

            // Set delivery photo field if empty
            var targetField = Object.values(frm.fields_dict).find(function(f) {
                return f.df && f.df.label === "Delivery Photo";
            });
            if (targetField && packTask.warehouse_pickup_photo && !frm.doc[targetField.df.fieldname]) {
                frm.doc[targetField.df.fieldname] = packTask.warehouse_pickup_photo;
                frm.refresh_field(targetField.df.fieldname);
            }

            // Fetch ALL image files attached to the Pack task
            frappe.call({
                method: 'frappe.client.get_list',
                args: {
                    doctype: 'File',
                    filters: { attached_to_doctype: 'Task', attached_to_name: packTask.name, is_private: ['in', [0, 1]] },
                    fields: ['file_url', 'file_name'],
                    limit_page_length: 50
                },
                async: true,
                callback: function(fr) {
                    var files = (fr.message || []).filter(function(f) {
                        return /\.(jpg|jpeg|png|gif|webp|bmp|heic|heif)$/i.test(f.file_url || '');
                    });
                    // Remove old preview
                    $('#pack_prepare_preview_wrapper').remove();
                    if (!files.length) return;

                    var html = '<div id="pack_prepare_preview_wrapper" style="margin-top:12px;margin-bottom:12px;padding:10px;border:1px solid #d1d8dd;border-radius:6px;background:#fafbfc;max-width:100%;overflow:hidden;">';
                    html += '<label class="control-label" style="color:#6c757d;font-weight:bold;margin-bottom:8px;display:block;">Pack / Prepare Photos (' + files.length + ')</label>';
                    html += '<div style="display:flex;flex-wrap:wrap;gap:8px;align-items:flex-start;max-width:100%;">';
                    files.forEach(function(f) {
                        var url = f.file_url || '';
                        var title = frappe.utils.escape_html(f.file_name || 'Photo');
                        if (url.indexOf('/private/files/') === 0) {
                            url = '/api/method/frappe.utils.file_manager.download_file?file_url=' + encodeURIComponent(url);
                        }
                        var safeUrl = frappe.utils.escape_html(url);
                        html += '<button type="button" class="btn btn-xs task-inspect-pack-photo-thumb" data-pack-photo-url="' + safeUrl + '" data-pack-photo-title="' + title + '" style="display:block;padding:0;border:0;background:transparent;line-height:0;">';
                        html += '<img src="' + safeUrl + '" title="' + title + '" style="width:76px;height:76px;object-fit:cover;border:1px solid #d1d8dd;border-radius:6px;background:#f8f9fa;cursor:pointer;" />';
                        html += '</button>';
                    });
                    html += '</div><div style="font-size:11px;color:#8d99a6;margin-top:6px;">Tap a photo to preview full size. Pinch to zoom on phone.</div></div>';
                    setTimeout(function() {
                        $('#pack_prepare_preview_wrapper').off('click.taskInspectPreview').on('click.taskInspectPreview', '.task-inspect-pack-photo-thumb', function(e) {
                            e.preventDefault();
                            e.stopPropagation();
                            if (window.task_inspect_returns_preview_pack_photo) window.task_inspect_returns_preview_pack_photo(this);
                            return false;
                        });
                    }, 0);
                    if (targetField && targetField.$wrapper) {
                        targetField.$wrapper.append(html);
                    } else {
                        // Fallback: append after the form body
                        frm.$wrapper.find('.form-layout').append(html);
                    }
                }
            });
        }
    });
}
window.task_inspect_returns_preview_pack_photo = function(btn) {
    var url = btn && btn.getAttribute('data-pack-photo-url');
    var title = (btn && btn.getAttribute('data-pack-photo-title')) || 'Photo';
    if (!url) return false;
    $('#task-inspect-photo-fullscreen').remove();

    var scale = 1, minScale = 0.5, maxScale = 6, x = 0, y = 0;
    var pointers = {}, dragStart = null, pinchStart = null;
    var overlay = $('<div id="task-inspect-photo-fullscreen" style="position:fixed;z-index:99999;left:0;top:0;width:100vw;height:100vh;background:rgba(0,0,0,0.94);display:flex;flex-direction:column;box-sizing:border-box;overflow:hidden;"></div>');
    var toolbar = $('<div style="flex:0 0 auto;display:flex;align-items:center;gap:8px;padding:10px;background:rgba(0,0,0,0.75);color:#fff;box-sizing:border-box;z-index:2;"></div>');
    var caption = $('<div style="flex:1;min-width:0;font-size:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;"></div>').text(title);
    var zoomOut = $('<button type="button" style="background:#fff;color:#111;border:0;border-radius:6px;padding:8px 11px;font-weight:bold;">âˆ’</button>');
    var zoomIn = $('<button type="button" style="background:#fff;color:#111;border:0;border-radius:6px;padding:8px 11px;font-weight:bold;">+</button>');
    var reset = $('<button type="button" style="background:#fff;color:#111;border:0;border-radius:6px;padding:8px 10px;font-weight:bold;">Reset</button>');
    var close = $('<button type="button" style="background:#fff;color:#111;border:0;border-radius:6px;padding:8px 12px;font-weight:bold;">Close</button>');
    var viewport = $('<div style="position:relative;flex:1 1 auto;overflow:hidden;touch-action:none;cursor:grab;background:#111;"></div>');
    var img = $('<img />').attr('src', url).attr('alt', title).css({position:'absolute', left:'50%', top:'50%', maxWidth:'96%', maxHeight:'96%', transformOrigin:'center center', userSelect:'none', webkitUserSelect:'none', touchAction:'none', borderRadius:'6px'});

    function clampScale(v) { return Math.max(minScale, Math.min(maxScale, v)); }
    function clampPan() {
        var rect = viewport[0].getBoundingClientRect();
        var baseW = img[0].clientWidth || rect.width;
        var baseH = img[0].clientHeight || rect.height;
        var visibleEdge = 80;
        var maxX = Math.max(visibleEdge, (baseW * scale + rect.width) / 2 - visibleEdge);
        var maxY = Math.max(visibleEdge, (baseH * scale + rect.height) / 2 - visibleEdge);
        x = Math.max(-maxX, Math.min(maxX, x));
        y = Math.max(-maxY, Math.min(maxY, y));
    }
    function applyTransform() { clampPan(); img.css('transform', 'translate(calc(-50% + ' + x + 'px), calc(-50% + ' + y + 'px)) scale(' + scale + ')'); }
    function zoomAt(newScale, cx, cy) {
        newScale = clampScale(newScale);
        var rect = viewport[0].getBoundingClientRect();
        var dx = cx - (rect.left + rect.width / 2) - x;
        var dy = cy - (rect.top + rect.height / 2) - y;
        var factor = newScale / scale;
        x -= dx * (factor - 1);
        y -= dy * (factor - 1);
        scale = newScale;
        applyTransform();
    }
    function pointDistance(a, b) { var dx = a.clientX - b.clientX, dy = a.clientY - b.clientY; return Math.sqrt(dx * dx + dy * dy); }
    function pointMid(a, b) { return { clientX: (a.clientX + b.clientX) / 2, clientY: (a.clientY + b.clientY) / 2 }; }

    zoomOut.on('click', function(e) { e.preventDefault(); e.stopPropagation(); var r = viewport[0].getBoundingClientRect(); zoomAt(scale - 0.25, r.left + r.width / 2, r.top + r.height / 2); return false; });
    zoomIn.on('click', function(e) { e.preventDefault(); e.stopPropagation(); var r = viewport[0].getBoundingClientRect(); zoomAt(scale + 0.25, r.left + r.width / 2, r.top + r.height / 2); return false; });
    reset.on('click', function(e) { e.preventDefault(); e.stopPropagation(); scale = 1; x = 0; y = 0; applyTransform(); return false; });
    close.on('click', function(e) { e.preventDefault(); e.stopPropagation(); overlay.remove(); return false; });
    viewport.on('wheel', function(e) { e.preventDefault(); var oe = e.originalEvent; zoomAt(scale * (oe.deltaY < 0 ? 1.12 : 0.88), oe.clientX, oe.clientY); return false; });
    viewport.on('pointerdown', function(e) {
        e.preventDefault(); viewport[0].setPointerCapture(e.originalEvent.pointerId); pointers[e.originalEvent.pointerId] = e.originalEvent;
        var ids = Object.keys(pointers);
        if (ids.length === 1) { dragStart = { clientX: e.originalEvent.clientX, clientY: e.originalEvent.clientY, x: x, y: y }; viewport.css('cursor', 'grabbing'); }
        if (ids.length === 2) { var p1 = pointers[ids[0]], p2 = pointers[ids[1]]; pinchStart = { dist: pointDistance(p1, p2), scale: scale, x: x, y: y, mid: pointMid(p1, p2) }; }
        return false;
    });
    viewport.on('pointermove', function(e) {
        if (!pointers[e.originalEvent.pointerId]) return false;
        pointers[e.originalEvent.pointerId] = e.originalEvent;
        var ids = Object.keys(pointers);
        if (ids.length >= 2 && pinchStart) {
            var p1 = pointers[ids[0]], p2 = pointers[ids[1]], mid = pointMid(p1, p2);
            x = pinchStart.x + (mid.clientX - pinchStart.mid.clientX);
            y = pinchStart.y + (mid.clientY - pinchStart.mid.clientY);
            scale = clampScale(pinchStart.scale * (pointDistance(p1, p2) / pinchStart.dist));
            applyTransform();
        } else if (ids.length === 1 && dragStart) {
            x = dragStart.x + (e.originalEvent.clientX - dragStart.clientX);
            y = dragStart.y + (e.originalEvent.clientY - dragStart.clientY);
            applyTransform();
        }
        return false;
    });
    viewport.on('pointerup pointercancel pointerleave', function(e) {
        delete pointers[e.originalEvent.pointerId];
        viewport.css('cursor', 'grab');
        dragStart = null;
        pinchStart = null;
        var ids = Object.keys(pointers);
        if (ids.length === 1) { var p = pointers[ids[0]]; dragStart = { clientX: p.clientX, clientY: p.clientY, x: x, y: y }; }
        return false;
    });

    toolbar.append(caption).append(zoomOut).append(zoomIn).append(reset).append(close);
    viewport.append(img);
    overlay.append(toolbar).append(viewport);
    $('body').append(overlay);
    applyTransform();
    return false;
};