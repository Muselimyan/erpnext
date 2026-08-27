#Requires -Version 5.1
param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check",
    [ValidateSet("test", "main")]
    [string]$Target = "test"
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$ConfigFolder = if ($Target -eq "test") { "test" } else { "prod" }
$ConfigPath = Join-Path (Join-Path $PSScriptRoot $ConfigFolder) "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$BaseUrl = if ($Target -eq "test") { "https://test.erpnext.am" } else { "https://erpnext.am" }
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }
function Get-ErpDoc([string]$DocType, [string]$Name) {
    try { return (Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)" -Headers $Headers -Method Get -TimeoutSec 30).data } catch { return $null }
}
function Put-ErpDoc([string]$DocType, [string]$Name, $Body) {
    $json = $Body | ConvertTo-Json -Depth 20 -Compress
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 30 | Out-Null
}
function Upsert-ClientScript([string]$Name, [string]$Script) {
    $existing = Get-ErpDoc "Client Script" $Name
    $body = @{ dt = "Task"; view = "Form"; enabled = 1; script = $Script }
    if ($existing) {
        Put-ErpDoc "Client Script" $Name $body
    } else {
        $body.name = $Name
        $json = $body | ConvertTo-Json -Depth 20 -Compress
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 30 | Out-Null
    }
}
function Upsert-ServerScript([string]$Name, [string]$Script) {
    $existing = Get-ErpDoc "Server Script" $Name
    $body = @{
        script_type = "DocType Event"
        reference_doctype = "Task"
        doctype_event = "Before Save"
        event_frequency = "All"
        disabled = 0
        script = $Script
    }
    if ($existing) {
        Put-ErpDoc "Server Script" $Name $body
    } else {
        $body.name = $Name
        $json = $body | ConvertTo-Json -Depth 20 -Compress
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 30 | Out-Null
    }
}

Write-Host "=== Account Details Task UI Cleanup ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

$ClientScriptName = "Task-Account Details UI Cleanup"
$existingClient = Get-ErpDoc "Client Script" $ClientScriptName
$photoField = Get-ErpDoc "Custom Field" "Task-custom_account_photos"
$sectionField = Get-ErpDoc "Custom Field" "Task-custom_account_details_section"

$hasClient = $null -ne $existingClient
$hasActionsCleanup = $existingClient -and $existingClient.script -match 'accountDetailsHideActions'
$hasStatusLeftCleanup = $existingClient -and $existingClient.script -match 'accountDetailsStatusLeft'
$hasPhotosVisibleCleanup = $existingClient -and $existingClient.script -match 'accountDetailsPhotosVisible'
$hasPhotosBoxCleanup = $existingClient -and $existingClient.script -match 'accountDetailsAddPhotosBox'
$hasNewDocPhotoCleanup = $existingClient -and $existingClient.script -match 'accountDetailsNewDocPhotoCleanup'
$accountAssignScript = Get-ErpDoc "Server Script" "Task-Account Details Default Assignment"
$hasAccountDefaultAssign = $accountAssignScript -and $accountAssignScript.script -match 'accounting.team@example.com'
$photoReady = $photoField -and $photoField.label -eq "Photos" -and $photoField.insert_after -eq "priority" -and $photoField.depends_on -eq 'eval:doc.task_kind === "Account details"'
$sectionHidden = $sectionField -and [string]$sectionField.hidden -eq "1"

Write-Host "Has Account details cleanup client script: $(if($hasClient){'Yes'}else{'No'})"
Write-Host "Has Account details Actions cleanup: $(if($hasActionsCleanup){'Yes'}else{'No'})"
Write-Host "Has Account details Status left cleanup: $(if($hasStatusLeftCleanup){'Yes'}else{'No'})"
Write-Host "Has Account details Photos visible cleanup: $(if($hasPhotosVisibleCleanup){'Yes'}else{'No'})"
Write-Host "Has Account details Add Photos box: $(if($hasPhotosBoxCleanup){'Yes'}else{'No'})"
Write-Host "Has Account details new-doc photo cleanup: $(if($hasNewDocPhotoCleanup){'Yes'}else{'No'})"
Write-Host "Has Account details default Accounting assignment: $(if($hasAccountDefaultAssign){'Yes'}else{'No'})"
Write-Host "Photos table relabeled/repositioned: $(if($photoReady){'Yes'}else{'No'})"
Write-Host "Old Account Details Documents section hidden: $(if($sectionHidden){'Yes'}else{'No'})"

if ($Mode -eq "Check") {
    if ($hasClient -and $hasActionsCleanup -and $hasStatusLeftCleanup -and $hasPhotosVisibleCleanup -and $hasPhotosBoxCleanup -and $hasNewDocPhotoCleanup -and $hasAccountDefaultAssign -and $photoReady -and $sectionHidden) { Write-Host "Status: fixed" -ForegroundColor Green } else { Write-Host "Status: needs deploy" -ForegroundColor Yellow }
    return
}

if (-not $photoField) { throw "Missing Task-custom_account_photos custom field" }
if (-not $sectionField) { throw "Missing Task-custom_account_details_section custom field" }

$backupPath = Join-Path $PSScriptRoot ("_backup_account_details_task_ui_cleanup_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".json")
@{ client_script = $existingClient; custom_account_photos = $photoField; custom_account_details_section = $sectionField } | ConvertTo-Json -Depth 30 | Set-Content -Path $backupPath -Encoding UTF8
Write-Host "Backup: $backupPath" -ForegroundColor Green

Put-ErpDoc "Custom Field" "Task-custom_account_photos" @{ label = "Photos"; insert_after = "priority"; depends_on = 'eval:doc.task_kind === "Account details"'; hidden = 0 }
Put-ErpDoc "Custom Field" "Task-custom_account_details_section" @{ hidden = 1; depends_on = 'eval:doc.task_kind === "__never_show_account_details_documents__"' }

$ClientScript = @'
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
    var is_account_details = taskKind === "account details";
    var account_only_hide = [
        "warehouse_pickup_photo",
        "warehouse_dropoff_photo",
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
    }
    if (!is_account_details) return;
    frm.set_df_property("subject", "reqd", 0);
    frm.toggle_display("subject", true);
    if (frm.fields_dict.subject && frm.fields_dict.subject.df) {
        frm.fields_dict.subject.df.reqd = 0;
    }
    task_account_details_add_new_accept_button(frm);
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
            var completeBtn = statusControl.find('#complete-task-btn').detach();
            statusControl.attr('data-account-details-status-left', 'accountDetailsStatusLeft').appendTo(leftColumn);
            if (completeBtn.length && !statusControl.find('#complete-task-btn').length) statusControl.append(completeBtn);
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
            statusControl.find('#complete-task-btn').show();
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
    if (taskKind !== "account details") return;
    if (!String(frm.doc.subject || '').trim()) {
        frm.set_value("subject", "Account details");
    }
}

function task_account_details_add_new_accept_button(frm) {
    if (!frm || !frm.is_new || !frm.is_new()) return;
    if (String(frm.doc.task_kind || '').trim().toLowerCase() !== "account details") return;
    if (frm.page && frm.page.clear_inner_toolbar) {
        frm.page.clear_inner_toolbar();
    }
    frm.add_custom_button(__("Accept / Start Task"), function() {
        task_account_details_prepare_subject(frm);
        frm.save().then(function() {
            frappe.call({
                method: "dispatch_task_accept",
                args: { task_name: frm.doc.name },
                freeze: true,
                freeze_message: __("Accepting task..."),
                callback: function() {
                    frm.reload_doc();
                }
            });
        });
    }).addClass("btn-primary");
}

function task_account_details_render_photos_box(frm, photosControl) {
    if (!photosControl || !photosControl.length) return;
    photosControl.find('.account-details-add-photos-box').remove();
    var box = $('<div class="account-details-add-photos-box" data-account-details-add-photos-box="accountDetailsAddPhotosBox" style="margin-top:10px;margin-bottom:12px;padding:8px 0;border:0;background:transparent;"></div>');
    var btn = $('<button class="btn btn-sm btn-primary" type="button" style="font-size:12px;padding:5px 14px;background:#000;border-color:#000;color:#fff;border-radius:5px;">+ Add Photos</button>');
    box.append(btn);
    photosControl.prepend(box);
    btn.on('click', function() {
        if (frm.is_new()) {
            frappe.msgprint(__('Please save the task before adding photos.'));
            return;
        }
        new frappe.ui.FileUploader({
            doctype: frm.doctype,
            docname: frm.doc.name,
            folder: 'Home/Attachments',
            allow_multiple: true,
            on_success: function() {
                task_account_details_render_photo_preview(frm, photosControl);
                setTimeout(function() { task_account_details_render_photo_preview(frm, photosControl); }, 1000);
                frm.reload_doc();
            }
        });
    });
    task_account_details_render_photo_preview(frm, photosControl);
    setTimeout(function() { task_account_details_render_photo_preview(frm, photosControl); }, 800);
    setTimeout(function() { task_account_details_render_photo_preview(frm, photosControl); }, 1800);
}

function task_account_details_render_photo_preview(frm, photosControl) {
    if (!photosControl || !photosControl.length) return;
    photosControl.find('.account-details-photo-gallery').remove();
    photosControl.find('[data-account-details-new-doc-photo-cleanup]').remove();
    if (frm.is_new()) {
        photosControl.append('<div data-account-details-new-doc-photo-cleanup="accountDetailsNewDocPhotoCleanup" style="font-size:11px;color:#8d99a6;margin-top:8px;">Photos will be available after saving this task.</div>');
        return;
    }

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
            var name = f.file_name || f.name || f.title || 'Photo';
            if (!url || seen[url]) return;
            if (!isImageFile({file_url: imageTestUrl(url), file_name: name})) return;
            seen[url] = true;
            images.push({file_url: url, file_name: name});
        });
        if (!images.length) return;
        var html = '<div class="account-details-photo-gallery" style="margin-top:12px;margin-bottom:12px;">';
        html += '<label style="font-weight:500;font-size:11px;color:#6c757d;margin-bottom:8px;display:block;">Attached Photos (' + images.length + ')</label>';
        html += '<div style="display:flex;flex-direction:column;align-items:flex-start;gap:8px;">';
        images.forEach(function(f) {
            var url = f.file_url || '';
            var title = frappe.utils.escape_html(f.file_name || 'Photo');
            html += '<a href="' + url + '" target="_blank" style="display:block;text-decoration:none;line-height:0;">';
            html += '<img src="' + url + '" title="' + title + '" style="width:90px;max-height:140px;object-fit:cover;border:1px solid #d1d8dd;border-radius:4px;background:#f8f9fa;" />';
            html += '</a>';
        });
        html += '</div></div>';
        photosControl.append(html);
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
'@

$ServerScriptName = "Task-Account Details Default Assignment"
$ServerScript = @'
if doc.get("task_kind") == "Account details":
    if not doc.get("subject"):
        doc.subject = "Account details"
    assignee = doc.get("custom_assigned_to") or "accounting.team@example.com"
    doc.custom_assigned_to = assignee
    doc.set("_assign", '["' + assignee + '"]')

    if not doc.is_new():
        exists = frappe.db.exists("ToDo", {
            "reference_type": "Task",
            "reference_name": doc.name,
            "allocated_to": assignee,
            "status": "Open"
        })
        if not exists:
            todo = frappe.new_doc("ToDo")
            todo.status = "Open"
            todo.allocated_to = assignee
            todo.reference_type = "Task"
            todo.reference_name = doc.name
            todo.description = doc.subject or doc.name
            todo.assigned_by = frappe.session.user
            todo.flags.ignore_permissions = True
            todo.insert()
'@

Upsert-ClientScript $ClientScriptName $ClientScript
Upsert-ServerScript $ServerScriptName $ServerScript
Write-Host "Account details Task UI cleanup and assignment default deployed" -ForegroundColor Green
