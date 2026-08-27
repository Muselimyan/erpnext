frappe.ui.form.on('Task', {
    refresh: function(frm) {
        task_mobile_form_layout_fix(frm);
        setTimeout(function() { task_mobile_form_layout_fix(frm); }, 250);
        setTimeout(function() { task_mobile_form_layout_fix(frm); }, 900);
        setTimeout(function() { task_mobile_form_layout_fix(frm); }, 1800);
        setTimeout(function() { task_mobile_form_layout_fix(frm); }, 2800);
        setTimeout(function() { task_mobile_form_layout_fix(frm); }, 4500);
        setTimeout(function() { task_mobile_form_layout_fix(frm); }, 7000);
        setTimeout(function() { task_mobile_pack_photo_button(frm); }, 1200);
    },
    after_save: function(frm) {
        setTimeout(function() { task_mobile_form_layout_fix(frm); }, 500);
        setTimeout(function() { task_mobile_pack_photo_button(frm); }, 800);
    }
});

function task_mobile_form_layout_fix(frm) {
    if (window.innerWidth > 768) return;
    var is_pack_task = !!(frm && frm.doc && frm.doc.task_kind === 'Pack / prepare items');
    document.body.classList.toggle('task-mobile-pack-clean', is_pack_task);

    if (!document.getElementById('task-mobile-form-layout-fix-style')) {
        var style = document.createElement('style');
        style.id = 'task-mobile-form-layout-fix-style';
        style.textContent = `
@media (max-width: 768px) {
    body[data-route^="Form/Task"] .form-tabs-list,
    body[data-route^="Form/Task"] .form-tabs {
        overflow-x: auto !important;
        overflow-y: hidden !important;
        flex-wrap: nowrap !important;
        white-space: nowrap !important;
    }
    body[data-route^="Form/Task"] [data-fieldname="subject"],
    body[data-route^="Form/Task"] [data-fieldname="subject"] .control-input-wrapper,
    body[data-route^="Form/Task"] [data-fieldname="subject"] .control-input {
        display: block !important;
        visibility: visible !important;
    }
    body[data-route^="Form/Task"] [data-fieldname="subject"] input,
    body[data-route^="Form/Task"] [data-fieldname="subject"] textarea {
        min-height: 38px !important;
        font-size: 15px !important;
    }
    body[data-route^="Form/Task"] .form-page {
        padding-bottom: 92px !important;
    }
    body.task-mobile-pack-clean[data-route^="Form/Task"] .page-head,
    body.task-mobile-pack-clean[data-route^="Form/Task"] .page-head .container,
    body.task-mobile-pack-clean[data-route^="Form/Task"] .page-head .container-fluid,
    body.task-mobile-pack-clean[data-route^="Form/Task"] .page-head .page-head-content {
        max-width: 100vw !important;
        min-width: 0 !important;
        overflow: hidden !important;
    }
    body.task-mobile-pack-clean[data-route^="Form/Task"] .page-head .page-head-content {
        display: flex !important;
        align-items: center !important;
        gap: 6px !important;
        flex-wrap: nowrap !important;
    }
    body.task-mobile-pack-clean[data-route^="Form/Task"] .task-mobile-pack-hidden,
    body.task-mobile-pack-clean[data-route^="Form/Task"] .page-head .title-area,
    body.task-mobile-pack-clean[data-route^="Form/Task"] .page-head .title-text {
        display: none !important;
        visibility: hidden !important;
    }
    body.task-mobile-pack-clean[data-route^="Form/Task"] .page-head .page-actions,
    body.task-mobile-pack-clean[data-route^="Form/Task"] .page-head .standard-actions,
    body.task-mobile-pack-clean[data-route^="Form/Task"] .page-head .custom-actions {
        min-width: 0 !important;
        max-width: calc(100vw - 56px) !important;
        margin-left: auto !important;
        display: flex !important;
        align-items: center !important;
        justify-content: flex-end !important;
        gap: 6px !important;
        overflow: hidden !important;
        flex: 1 1 auto !important;
        white-space: nowrap !important;
    }
    body.task-mobile-pack-clean[data-route^="Form/Task"] .page-head .page-actions .btn,
    body.task-mobile-pack-clean[data-route^="Form/Task"] .page-head .standard-actions .btn,
    body.task-mobile-pack-clean[data-route^="Form/Task"] .page-head .custom-actions .btn,
    body.task-mobile-pack-clean[data-route^="Form/Task"] .page-head .btn {
        flex: 0 0 auto !important;
        min-width: 36px !important;
        max-width: 42px !important;
        width: 38px !important;
        height: 38px !important;
        padding: 6px !important;
        overflow: hidden !important;
        text-overflow: clip !important;
    }
    body.task-mobile-pack-clean[data-route^="Form/Task"] .task-mobile-pack-summary {
        margin: 8px 0 12px 0 !important;
        padding: 10px 12px !important;
        border: 1px solid var(--border-color, #d1d8dd) !important;
        border-radius: 10px !important;
        background: #f8fafc !important;
        color: var(--text-color, #192734) !important;
        box-shadow: 0 1px 2px rgba(0,0,0,0.04) !important;
    }
    body.task-mobile-pack-clean[data-route^="Form/Task"] .task-mobile-pack-summary-title {
        display: block !important;
        font-size: 16px !important;
        font-weight: 700 !important;
        line-height: 1.25 !important;
        overflow-wrap: anywhere !important;
    }
    body.task-mobile-pack-clean[data-route^="Form/Task"] .task-mobile-pack-summary-meta {
        display: block !important;
        margin-top: 4px !important;
        color: var(--text-muted, #6c7680) !important;
        font-size: 12px !important;
        line-height: 1.3 !important;
        overflow-wrap: anywhere !important;
    }
    body.task-mobile-pack-clean[data-route^="Form/Task"] [data-fieldname="subject"] {
        margin-top: 4px !important;
    }
    body.task-mobile-pack-clean[data-route^="Form/Task"] .section-head,
    body.task-mobile-pack-clean[data-route^="Form/Task"] .control-label {
        font-size: 14px !important;
    }
    body.task-mobile-pack-clean[data-route^="Form/Task"] .frappe-control {
        margin-bottom: 12px !important;
    }
    body.task-mobile-pack-clean[data-route^="Form/Task"] #mobile-back-btn,
    body.task-mobile-pack-clean[data-route^="Form/Task"] .mobile-back-btn,
    body.task-mobile-pack-clean[data-route^="Form/Task"] .btn-mobile-back,
    body.task-mobile-pack-clean[data-route^="Form/Task"] [data-mobile-back="1"] {
        display: none !important;
        visibility: hidden !important;
    }
    body.task-mobile-pack-clean[data-route^="Form/Task"] [data-fieldname="custom_product_lines"],
    body.task-mobile-pack-clean[data-route^="Form/Task"] [data-fieldname="custom_task_product_work"],
    body.task-mobile-pack-clean[data-route^="Form/Task"] [data-fieldname="custom_packing_items"],
    body.task-mobile-pack-clean[data-route^="Form/Task"] .form-grid,
    body.task-mobile-pack-clean[data-route^="Form/Task"] .grid-body,
    body.task-mobile-pack-clean[data-route^="Form/Task"] .grid-static-col,
    body.task-mobile-pack-clean[data-route^="Form/Task"] .grid-row {
        font-size: 13px !important;
    }
    body.task-mobile-pack-clean[data-route^="Form/Task"] .grid-body,
    body.task-mobile-pack-clean[data-route^="Form/Task"] .form-grid {
        overflow-x: auto !important;
        -webkit-overflow-scrolling: touch !important;
    }
    body.task-mobile-pack-clean[data-route^="Form/Task"] .grid-row,
    body.task-mobile-pack-clean[data-route^="Form/Task"] .grid-heading-row {
        min-width: 330px !important;
    }
    body.task-mobile-pack-clean[data-route^="Form/Task"] .grid-static-col {
        min-height: 54px !important;
        padding: 8px 7px !important;
        white-space: normal !important;
        overflow-wrap: anywhere !important;
        line-height: 1.25 !important;
    }
    body.task-mobile-pack-clean[data-route^="Form/Task"] .grid-static-col input[type="checkbox"],
    body.task-mobile-pack-clean[data-route^="Form/Task"] .grid-static-col .checkbox input {
        width: 22px !important;
        height: 22px !important;
        min-width: 22px !important;
        min-height: 22px !important;
    }
    body.task-mobile-pack-clean[data-route^="Form/Task"] .grid-empty,
    body.task-mobile-pack-clean[data-route^="Form/Task"] .grid-body .rows {
        padding-bottom: 72px !important;
    }
}
`;
        document.head.appendChild(style);
    }

    try {
        if (frm && frm.fields_dict && frm.fields_dict.subject) {
            frm.toggle_display('subject', true);
            frm.set_df_property('subject', 'hidden', 0);
            frm.set_df_property('subject', 'reqd', 0);
        }
        $(frm.wrapper).find('[data-fieldname="subject"]').closest('.frappe-control').show().css({ display: 'block', visibility: 'visible' });
        var titleText = document.querySelector('body[data-route^="Form/Task"] .page-head .title-text');
        if (titleText) {
            var fullText = titleText.textContent.trim();
            if (fullText) titleText.setAttribute('title', fullText);
        }

        if (is_pack_task && frm && frm.wrapper) {
            task_mobile_pack_cleanup(frm);
            task_mobile_pack_photo_button(frm);
        }
    } catch (e) {}
}

function task_mobile_pack_cleanup(frm) {
    ['#mobile-back-btn', '.mobile-back-btn', '.btn-mobile-back', '[data-mobile-back="1"]'].forEach(function(sel) {
        document.querySelectorAll(sel).forEach(function(btn) {
            btn.style.setProperty('display', 'none', 'important');
            btn.style.setProperty('visibility', 'hidden', 'important');
        });
    });

    ['task-mobile-hide-desktop-custom-actions', 'task-mobile-compact-actions'].forEach(function(id) {
        var el = document.getElementById(id);
        if (el) el.remove();
    });

    var $w = $(frm.wrapper);
    var subject = (frm.doc.subject || '').trim();
    var dispatch_case = (frm.doc.dispatch_case || '').trim();
    var status = (frm.doc.dispatch_case_status || frm.doc.custom_dispatch_case_status || '').trim();
    var customer = (frm.doc.customer || '').trim();

    var $target = $w.find('.form-layout').first();
    if (!$target.length) $target = $w.find('.layout-main-section').first();
    if ($target.length && (subject || dispatch_case || status || customer)) {
        var $summary = $w.find('.task-mobile-pack-summary');
        if (!$summary.length) {
            $summary = $('<div class="task-mobile-pack-summary"><span class="task-mobile-pack-summary-title"></span><span class="task-mobile-pack-summary-meta"></span></div>');
            $target.prepend($summary);
        }
        $summary.find('.task-mobile-pack-summary-title').text(subject || 'Pack Task');
        var meta = [];
        if (dispatch_case) meta.push('Dispatch Case: ' + dispatch_case);
        if (status) meta.push('Status: ' + status);
        if (customer) meta.push('Customer: ' + customer);
        $summary.find('.task-mobile-pack-summary-meta').text(meta.join(' | '));
    }

    var hide_fields = [
        'completed_at',
        'task_kind',
        'custom_assigned_to',
        'custom_accepted_at',
        'accepted_at'
    ];
    hide_fields.forEach(function(fieldname) {
        $w.find('[data-fieldname="' + fieldname + '"]').closest('.frappe-control').addClass('task-mobile-pack-hidden');
    });

    $w.find('[data-fieldname="customer"]').each(function() {
        var $control = $(this).closest('.frappe-control');
        var value = ($control.find('input, textarea').val() || $control.find('.control-value').text() || '').trim();
        $control.toggleClass('task-mobile-pack-hidden', !value);
    });

    $w.find('[data-fieldname="subject"]').each(function() {
        var control = $(this).closest('.frappe-control')[0] || this;
        if (control) {
            control.classList.add('task-mobile-pack-hidden');
            control.style.setProperty('display', 'none', 'important');
            control.style.setProperty('visibility', 'hidden', 'important');
        }
    });
    $w.find('.control-label, label').filter(function() {
        return $.trim($(this).text()) === 'Subject';
    }).each(function() {
        var control = $(this).closest('.frappe-control')[0] || $(this).parent()[0];
        if (control) {
            control.classList.add('task-mobile-pack-hidden');
            control.style.setProperty('display', 'none', 'important');
            control.style.setProperty('visibility', 'hidden', 'important');
        }
    });

    $w.find('[data-fieldname="dispatch_case"]').closest('.frappe-control').removeClass('task-mobile-pack-hidden');
    $w.find('[data-fieldname="custom_product_lines"], [data-fieldname="custom_task_product_work"], [data-fieldname="custom_packing_items"]').closest('.frappe-control').removeClass('task-mobile-pack-hidden');
}

function task_mobile_pack_photo_button(frm) {
    if (!frm || !frm.doc || !frm.wrapper || window.innerWidth > 768) return;
    var config = task_mobile_photo_config(frm);
    if (!config) return;
    var $w = $(frm.wrapper);
    var $btn = $w.find('#' + config.button_id);
    if (!$btn.length) {
        $btn = $('<button id="' + config.button_id + '" class="btn btn-sm btn-primary" type="button" style="font-size:12px;padding:6px 16px;background:#000;border-color:#000;color:#fff;border-radius:7px;margin-top:8px;margin-bottom:12px;display:inline-block;">' + config.label + '</button>');
        $btn.on('click', function() {
            var openUploader = function() {
                frappe.call({
                    method: 'frappe.client.get_count',
                    args: { doctype: 'File', filters: { attached_to_doctype: 'Task', attached_to_name: frm.doc.name } },
                    callback: function(r) {
                        var existing = r.message || 0;
                        if (existing >= 5) {
                            frappe.msgprint(__('Maximum 5 photos/files can be attached.'));
                            return;
                        }
                        new frappe.ui.FileUploader({
                            doctype: 'Task',
                            docname: frm.doc.name,
                            folder: 'Home/Attachments',
                            allow_multiple: true,
                            restrictions: { allowed_file_types: ['image/*'], max_number_of_files: 5 - existing },
                            on_success: function(file_doc) {
                                var url = file_doc && (file_doc.file_url || file_doc.url || file_doc.file_name);
                                task_mobile_set_photo_field(frm, config, url, true);
                                task_mobile_photo_preview(frm);
                                setTimeout(function() { task_mobile_photo_preview(frm); }, 800);
                            }
                        });
                    }
                });
            };
            if (frm.is_new() || !frm.doc.name || frm.doc.name.indexOf('new-') === 0) {
                frm.save().then(function() { openUploader(); });
            } else {
                openUploader();
            }
        });
    }
    var $anchor = $w.find('[data-fieldname="' + config.fieldname + '"]').closest('.frappe-control').first();
    if (!$anchor.length) {
        $anchor = $w.find('.control-label, label').filter(function() { return $.trim($(this).text()) === config.field_label; }).closest('.frappe-control').first();
    }
    if ($anchor.length) {
        $btn.detach().insertAfter($anchor.find('.control-input-wrapper, .control-value').last());
        task_mobile_photo_preview(frm);
        setTimeout(function() { task_mobile_photo_preview(frm); }, 900);
    }
}

function task_mobile_photo_config(frm) {
    var task_kind = String((frm && frm.doc && frm.doc.task_kind) || '').trim();
    if (task_kind === 'Pack / prepare items') {
        return { button_id: 'task-mobile-pack-add-pickup-photos-btn', preview_id: 'task-mobile-pack-photo-preview', label: '+ Add Pickup Photos', fieldname: 'warehouse_pickup_photo', field_label: 'Warehouse Pickup Photo' };
    }
    if (task_kind === 'Pickup Returns') {
        return { button_id: 'task-mobile-pickup-returns-add-dropoff-photos-btn', preview_id: 'task-mobile-pickup-returns-photo-preview', label: '+ Add Drop-off Photos', fieldname: 'warehouse_dropoff_photo', field_label: 'Warehouse Drop-off Photo' };
    }
    return null;
}

function task_mobile_photo_preview(frm) {
    if (!frm || !frm.doc || !frm.doc.name || !frm.wrapper || frm.is_new()) return;
    var config = task_mobile_photo_config(frm);
    if (!config) return;
    var $w = $(frm.wrapper);
    var $btn = $w.find('#' + config.button_id);
    if (!$btn.length) return;
    var $host = $w.find('#' + config.preview_id);
    if (!$host.length) {
        $host = $('<div id="' + config.preview_id + '" style="margin-top:8px;margin-bottom:12px;"></div>');
        $btn.after($host);
    }

    function isImageFile(f) {
        var path = ((f.file_url || f.url || f.href || '') + ' ' + (f.file_name || f.name || f.title || '')).toLowerCase();
        return /\.(jpg|jpeg|png|gif|webp|bmp|heic|heif)(\?|#|$)/i.test(path);
    }
    function normalizeUrl(url) {
        if (!url) return '';
        if (url.indexOf('/api/method/frappe.utils.file_manager.download_file') === 0) return url;
        if (url.indexOf('/private/files/') === 0) return '/api/method/frappe.utils.file_manager.download_file?file_url=' + encodeURIComponent(url);
        return url;
    }
    function imageTestUrl(url) {
        if (!url) return '';
        var marker = 'file_url=';
        var idx = url.indexOf(marker);
        if (idx >= 0) return decodeURIComponent(url.substring(idx + marker.length));
        return url;
    }
    function render(files) {
        var seen = {};
        var images = [];
        (files || []).forEach(function(f) {
            var url = normalizeUrl(f.file_url || f.url || f.href || '');
            var name = f.file_name || f.name || f.title || 'Photo';
            if (!url || seen[url]) return;
            if (!isImageFile({file_url: imageTestUrl(url), file_name: name})) return;
            seen[url] = true;
            images.push({file_url: url, file_name: name});
        });
        if (!images.length) {
            $host.empty();
            return;
        }
        task_mobile_set_photo_field(frm, config, images[0].file_url, false);
        var html = '<div style="font-size:11px;color:#6c757d;margin-bottom:6px;">Attached Photos (' + images.length + ')</div>';
        html += '<div style="display:flex;flex-wrap:wrap;gap:8px;align-items:flex-start;">';
        images.forEach(function(f) {
            var url = f.file_url || '';
            var title = frappe.utils.escape_html(f.file_name || 'Photo');
            html += '<a href="' + url + '" target="_blank" style="display:block;text-decoration:none;line-height:0;">';
            html += '<img src="' + url + '" title="' + title + '" style="width:76px;height:76px;object-fit:cover;border:1px solid #d1d8dd;border-radius:6px;background:#f8f9fa;" />';
            html += '</a>';
        });
        html += '</div>';
        $host.html(html);
    }
    frappe.call({
        method: 'frappe.client.get_list',
        args: {
            doctype: 'File',
            filters: {
                attached_to_doctype: 'Task',
                attached_to_name: frm.doc.name,
                is_private: ['in', [0, 1]]
            },
            fields: ['file_url', 'file_name', 'is_private'],
            order_by: 'creation desc',
            limit_page_length: 50
        },
        callback: function(r) {
            render(r.message || []);
        }
    });
}

function task_mobile_set_photo_field(frm, config, url, save_now) {
    if (!frm || !frm.doc || !config || !url) return;
    if (frm.doc[config.fieldname]) return;
    if (frm.fields_dict && frm.fields_dict[config.fieldname]) {
        frm.set_value(config.fieldname, url);
        if (save_now && !frm.is_new()) {
            frm.save().then(function() {
                task_mobile_photo_preview(frm);
            });
        }
    } else if (!frm.is_new()) {
        frappe.call({
            method: 'frappe.client.set_value',
            args: {
                doctype: 'Task',
                name: frm.doc.name,
                fieldname: config.fieldname,
                value: url
            },
            callback: function() {
                frm.doc[config.fieldname] = url;
                task_mobile_photo_preview(frm);
            }
        });
    }
}
