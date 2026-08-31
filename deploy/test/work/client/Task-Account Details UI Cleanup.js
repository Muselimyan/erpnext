// Name: Task-Account Details UI Cleanup
// DocType: Task
// Enabled: 1
// ---

frappe.ui.form.on("Task", {
    validate(frm) {
        task_account_details_prepare_subject(frm);
    },
    before_save(frm) {
        task_account_details_prepare_subject(frm);
    },
    refresh(frm) {
        task_account_details_ui_cleanup(frm);
        setTimeout(function() { task_account_details_ui_cleanup(frm); }, 200);
        setTimeout(function() { task_account_details_ui_cleanup(frm); }, 800);
        setTimeout(function() { task_account_details_ui_cleanup(frm); }, 1600);
        setTimeout(function() { task_account_details_ui_cleanup(frm); }, 3000);
    },
    task_kind(frm) {
        task_account_details_ui_cleanup(frm);
    }
});

function task_account_details_ui_cleanup(frm) {
    if (!frm || frm.doctype !== "Task") return;
    var taskKind = String(frm.doc.task_kind || '').trim().toLowerCase();
    var is_account_details = taskKind === "account details: entry" || taskKind === "account details: processing";
    var account_only_hide = [
        "custom_product_work_section",
        "custom_task_product_summary",
        "custom_task_scan_barcode",
        "custom_task_scan_qty",
        "custom_task_scan_result",
        "custom_product_work_column",
        "custom_task_product_warning",
        "custom_task_add_item_code",
        "custom_task_add_qty",
        "custom_task_add_batch_no",
        "custom_task_add_unit_price",
        "custom_account_details_section"
    ];
    account_only_hide.forEach(function(fieldname) {
        if (frm.fields_dict[fieldname]) {
            frm.toggle_display(fieldname, !is_account_details);
        }
    });
    if (frm.fields_dict.custom_account_photos) {
        frm.set_df_property("custom_account_photos", "label", "Photos");
        frm.toggle_display("custom_account_photos", is_account_details);
        window._photoLog && window._photoLog('acct', 'custom_account_photos field: visible=' + is_account_details + ' (task_kind="' + (frm.doc.task_kind || '') + '")');
    }
    if (!is_account_details) return;
    frm.set_df_property("subject", "reqd", 0);
    frm.toggle_display("subject", true);
    if (frm.fields_dict.subject && frm.fields_dict.subject.df) {
        frm.fields_dict.subject.df.reqd = 0;
    }
    // Accept button now handled by Task-Action Buttons.js for all task kinds
    setTimeout(function() {
        var wrapper = $(frm.wrapper);
        wrapper.find('[data-fieldname="custom_product_work_section"]').closest('.form-section').hide();
        wrapper.find('[data-fieldname="custom_account_details_section"]').closest('.form-section').hide();
        ["Warehouse Pickup Photo", "Warehouse Drop-off Photo", "Products / Dispatch Work", "Product Lines", "Barcode Scanning (Optional)"].forEach(function(label) {
            wrapper.find('.section-head, .control-label, label').filter(function() {
                return $.trim($(this).text()) === label;
            }).each(function() {
                var section = $(this).closest('.form-section');
                var control = $(this).closest('.frappe-control');
                if (label === 'Barcode Scanning (Optional)') {
                    $(this).text('Status');
                } else if (section.length && (label === 'Products / Dispatch Work' || label === 'Product Lines')) {
                    section.hide();
                } else if (control.length) {
                    control.hide();
                }
            });
        });
        wrapper.find('.section-head').filter(function() {
            var text = $.trim($(this).text());
            return text === 'Barcode Scanning (Optional)' || text === 'Task Status & Priority';
        }).text('Status');
        ["custom_task_scan_barcode", "custom_task_scan_qty", "custom_task_scan_result", "custom_task_product_warning", "custom_task_add_item_code", "custom_task_add_qty", "custom_task_add_batch_no", "custom_task_add_unit_price"].forEach(function(fieldname) {
            wrapper.find('[data-fieldname="' + fieldname + '"]').closest('.frappe-control').hide();
            wrapper.find('.frappe-control[data-fieldname="' + fieldname + '"]').hide();
        });
        ["Warehouse Pickup Photo", "Warehouse Drop-off Photo", "Scan Product Barcode", "Scan Qty", "Last Scan Result", "Product Work Warning", "Choose Product", "Product Qty", "Batch / LOT", "Unit Price"].forEach(function(label) {
            wrapper.find('.control-label, label').filter(function() {
                return $.trim($(this).text()) === label;
            }).closest('.frappe-control').hide();
        });
        $('.page-actions .btn, .page-actions button, .custom-actions .btn, .custom-actions button').filter(function() {
            var text = $.trim($(this).text());
            return text === 'Actions' || text.indexOf('Products / Dispatch Work') >= 0;
        }).attr('data-account-details-actions-hidden', 'accountDetailsHideActions').hide().closest('.btn-group').hide();
        $('.dropdown-menu a, .dropdown-menu button').filter(function() {
            var text = $.trim($(this).text());
            return text === 'Products / Dispatch Work' || text === 'Open Dispatch Case' || text === 'Open Dispatch Items';
        }).closest('li, .dropdown-item, a, button').hide();
        var statusControl = wrapper.find('[data-fieldname="status"]').closest('.frappe-control');
        var priorityControl = wrapper.find('[data-fieldname="priority"]').closest('.frappe-control');
        var statusSection = statusControl.closest('.form-section');
        var leftColumn = statusSection.find('.form-column').first();
        if (leftColumn.length && statusControl.length) {
            statusControl.attr('data-account-details-status-left', 'accountDetailsStatusLeft').appendTo(leftColumn);
            if (priorityControl.length) priorityControl.appendTo(leftColumn);
            leftColumn.css({'float':'none','width':'360px','max-width':'100%','margin-left':'0','display':'block'});
            statusSection.find('.form-column').each(function(index) {
                if (index > 0) $(this).hide();
            });
            leftColumn.find('.frappe-control').each(function() {
                var fieldname = $(this).attr('data-fieldname') || $(this).find('[data-fieldname]').attr('data-fieldname') || '';
                var labelText = $.trim($(this).find('.control-label, label').first().text());
                if ((fieldname && fieldname !== 'status' && fieldname !== 'priority') || ["Warehouse Pickup Photo", "Warehouse Drop-off Photo", "Scan Product Barcode", "Scan Qty", "Last Scan Result", "Product Work Warning", "Choose Product", "Product Qty", "Batch / LOT", "Unit Price"].indexOf(labelText) >= 0) {
                    $(this).hide();
                }
            });
            statusControl.show();
            priorityControl.show();
        }
        var photosControl = wrapper.find('[data-fieldname="custom_account_photos"]').closest('.frappe-control');
        if (photosControl.length) {
            photosControl.hide();
        }
        var photosBoxHost = wrapper.find('#account-details-photos-box-host');
        if (!photosBoxHost.length) {
            photosBoxHost = $('<div id="account-details-photos-box-host" class="frappe-control" data-account-details-photos-visible="accountDetailsPhotosVisible" style="margin-top:6px;margin-bottom:12px;"></div>');
        }
        var subjectControl = wrapper.find('[data-fieldname="subject"]').closest('.frappe-control');
        if (subjectControl.length) {
            photosBoxHost.insertAfter(subjectControl);
        } else if (statusControl.length) {
            photosBoxHost.insertBefore(statusControl);
        } else if (leftColumn.length) {
            photosBoxHost.prependTo(leftColumn);
        }
        photosBoxHost.show();
        statusSection.show();
        task_account_details_render_photos_box(frm, photosBoxHost);
    }, 100);
}

function task_account_details_prepare_subject(frm) {
    if (!frm || frm.doctype !== "Task") return;
    var taskKind = String(frm.doc.task_kind || '').trim().toLowerCase();
    if (taskKind !== "account details: entry" && taskKind !== "account details: processing") return;
    if (!String(frm.doc.subject || '').trim()) {
        frm.set_value("subject", "Account details");
    }
}

// Accept button removed — now handled by Task-Action Buttons.js for all task kinds

function task_account_details_render_photos_box(frm, photosControl) {
    if (!photosControl || !photosControl.length) {
        window._photoWarn && window._photoWarn('acct', 'SKIP: no photosControl');
        return;
    }
    var _roles = frappe.user_roles || [];
    var _isAdmin = _roles.indexOf('System Manager') !== -1 || _roles.indexOf('Administrator') !== -1 || frappe.session.user === 'Administrator';
    var _canEdit = _isAdmin || (frm.doc.custom_accepted_by && frm.doc.custom_accepted_by === frappe.session.user);
    window._photoLog && window._photoLog('acct', 'ENTER task=' + (frm.doc.name || '?') + ' canEdit=' + _canEdit + ' (isAdmin=' + _isAdmin + ', accepted_by="' + (frm.doc.custom_accepted_by || '') + '", user="' + frappe.session.user + '")');
    photosControl.find('.account-details-add-photos-box').remove();
    if (_canEdit) {
        window._photoLog && window._photoLog('acct', 'upload button created');
        var box = $('<div class="account-details-add-photos-box" data-account-details-add-photos-box="accountDetailsAddPhotosBox" style="margin-top:10px;margin-bottom:12px;padding:8px 0;border:0;background:transparent;"></div>');
        var btn = $('<button class="btn btn-sm btn-primary" type="button" style="font-size:12px;padding:5px 14px;background:#000;border-color:#000;color:#fff;border-radius:5px;">+ Add Photos</button>');
        box.append(btn);
        photosControl.prepend(box);
        btn.on('click', function() {
            if (frm.is_new()) {
                frappe.msgprint(__('Please save the task before adding photos.'));
                return;
            }
            window._photoLog && window._photoLog('acct', 'upload button clicked, opening FileUploader');
            new frappe.ui.FileUploader({
                doctype: frm.doctype,
                docname: frm.doc.name,
                folder: 'Home/Attachments',
                allow_multiple: true,
                on_success: function() {
                    window._photoLog && window._photoLog('acct', 'upload on_success, refreshing preview');
                    task_account_details_render_photo_preview(frm, photosControl, _canEdit);
                    setTimeout(function() { task_account_details_render_photo_preview(frm, photosControl, _canEdit); }, 1000);
                    frm.reload_doc();
                }
            });
        });
    } else {
        window._photoLog && window._photoLog('acct', 'upload button NOT created (canEdit=false)');
    }
    task_account_details_render_photo_preview(frm, photosControl, _canEdit);
    setTimeout(function() { task_account_details_render_photo_preview(frm, photosControl, _canEdit); }, 800);
    setTimeout(function() { task_account_details_render_photo_preview(frm, photosControl, _canEdit); }, 1800);
}

function task_account_details_render_photo_preview(frm, photosControl, canEdit) {
    if (!photosControl || !photosControl.length) return;
    photosControl.find('.account-details-photo-gallery').remove();
    photosControl.find('[data-account-details-new-doc-photo-cleanup]').remove();
    if (frm.is_new()) {
        window._photoLog && window._photoLog('acct-preview', 'SKIP: is_new');
        photosControl.append('<div data-account-details-new-doc-photo-cleanup="accountDetailsNewDocPhotoCleanup" style="font-size:11px;color:#8d99a6;margin-top:8px;">Photos will be available after saving this task.</div>');
        return;
    }
    window._photoLog && window._photoLog('acct-preview', 'ENTER task=' + (frm.doc.name || '?') + ' canEdit=' + canEdit);

    function isImageFile(f) {
        var path = ((f.file_url || f.url || f.href || '') + ' ' + (f.file_name || f.name || f.title || '')).toLowerCase();
        return /\.(jpg|jpeg|png|gif|webp|bmp|heic|heif)(\?|#|$)/i.test(path);
    }

    function normalizeUrl(url) {
        if (!url) return '';
        if (url.indexOf('/api/method/frappe.utils.file_manager.download_file') === 0) return url;
        if (url.indexOf('/private/files/') === 0) return '/api/method/frappe.utils.file_manager.download_file?file_url=' + encodeURIComponent(url);
        if (url.indexOf('/files/') === 0) return url;
        if (url.indexOf('http') === 0) return url;
        return url;
    }

    function imageTestUrl(url) {
        if (!url) return '';
        var marker = 'file_url=';
        var idx = url.indexOf(marker);
        if (idx >= 0) {
            return decodeURIComponent(url.substring(idx + marker.length));
        }
        return url;
    }

    function render(files) {
        photosControl.find('.account-details-photo-gallery').remove();
        var seen = {};
        var images = [];
        (files || []).forEach(function(f) {
            var url = normalizeUrl(f.file_url || f.url || f.href || '');
            var displayName = f.file_name || f.title || 'Photo';
            var docName = f.name || '';
            if (!url || seen[url]) return;
            if (!isImageFile({file_url: imageTestUrl(url), file_name: displayName})) return;
            seen[url] = true;
            images.push({file_url: url, file_name: displayName, doc_name: docName});
        });
        if (!images.length) {
            window._photoLog && window._photoLog('acct-preview', 'no images found');
            return;
        }
        window._photoLog && window._photoLog('acct-preview', 'rendered ' + images.length + ' thumbnails (delete buttons: ' + (canEdit ? 'yes' : 'no') + ')');
        var html = '<div class="account-details-photo-gallery" style="margin-top:12px;margin-bottom:12px;">';
        html += '<label style="font-weight:500;font-size:11px;color:#6c757d;margin-bottom:8px;display:block;">Attached Photos (' + images.length + ')</label>';
        html += '<div style="display:flex;flex-wrap:wrap;align-items:flex-start;gap:8px;">';
        images.forEach(function(f) {
            var url = f.file_url || '';
            var title = frappe.utils.escape_html(f.file_name || 'Photo');
            var safeUrl = frappe.utils.escape_html(url);
            var safeDocName = frappe.utils.escape_html(f.doc_name || '');
            html += '<div style="position:relative;display:inline-block;">';
            html += '<button type="button" class="btn btn-xs task-photo-preview-thumb" data-photo-url="' + safeUrl + '" data-photo-title="' + title + '" onclick="window.task_photo_fullscreen_preview(this)" style="display:block;padding:0;border:0;background:transparent;line-height:0;">';
            html += '<img src="' + safeUrl + '" title="' + title + '" style="width:90px;max-height:140px;object-fit:cover;border:1px solid #d1d8dd;border-radius:4px;background:#f8f9fa;" />';
            html += '</button>';
            if (canEdit) {
                html += '<button type="button" class="task-photo-delete-btn" data-file-doc-name="' + safeDocName + '" data-file-url="' + safeUrl + '" onclick="window.task_photo_delete_file(this)" style="position:absolute;top:-4px;right:-4px;width:20px;height:20px;border-radius:50%;border:none;background:#e74c3c;color:#fff;font-size:12px;line-height:20px;text-align:center;padding:0;cursor:pointer;z-index:1;">x</button>';
            }
            html += '</div>';
        });
        html += '</div></div>';
        photosControl.append(html);
    }

    window._photoLog && window._photoLog('acct-preview', 'fetching files for task=' + frm.doc.name + '...');
    frappe.call({
        method: 'frappe.client.get_list',
        args: {
            doctype: 'File',
            filters: {
                attached_to_doctype: 'Task',
                attached_to_name: frm.doc.name,
                is_private: ['in', [0, 1]]
            },
            fields: ['name', 'file_url', 'file_name', 'is_private'],
            order_by: 'creation desc',
            limit_page_length: 50
        },
        callback: function(r) {
            var files = r.message || [];
            window._photoLog && window._photoLog('acct-preview', 'fetched ' + files.length + ' files');
            render(files);
        },
        error: function(err) {
            window._photoErr && window._photoErr('acct-preview', 'ERROR fetching files', err);
        }
    });
}