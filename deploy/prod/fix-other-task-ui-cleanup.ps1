#Requires -Version 5.1
param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

function Enc([string]$s) { [uri]::EscapeDataString($s) }
function Get-ErpDoc([string]$DocType, [string]$Name) {
    try { return (Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)" -Headers $Headers -Method Get -TimeoutSec 30).data } catch { return $null }
}
function Upsert-ErpDoc([string]$DocType, [string]$Name, $Body) {
    $Existing = Get-ErpDoc $DocType $Name
    $Json = $Body | ConvertTo-Json -Depth 40 -Compress
    if ($Existing) {
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 30 | Out-Null
        return [pscustomobject]@{ action = "updated"; name = $Name }
    }
    $Body.name = $Name
    $Json = $Body | ConvertTo-Json -Depth 40 -Compress
    $Created = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 30).data
    return [pscustomobject]@{ action = "created"; name = $Created.name }
}

Write-Host "=== Other Task UI Cleanup + Entry/Processing Flow ===" -ForegroundColor Cyan
Write-Host "Target: $BaseUrl" -ForegroundColor Yellow

$TaskKindOptions = @(
    "Order accepting",
    "Order entry",
    "Pack / prepare items",
    "Dispatch picking / hand-off",
    "Delivery",
    "Return Call",
    "Return to warehouse (aborted delivery / cancelled order)",
    "Pickup Returns",
    "Return drop-off at warehouse",
    "Returns processing / verification",
    "Returns restocking",
    "Invoice preparation / create invoice",
    "Debt Collection",
    "Distribute Payment",
    "Payment Received",
    "Discount Approval",
    "Purchase Approval",
    "Write-off Approval",
    "Account Details: Entry",
    "Account Details: Processing",
    "Other: Entry",
    "Other: Processing",
    "Debt Closure Approval"
) -join "`n"

$TaskKindField = [ordered]@{ dt = "Task"; fieldname = "task_kind"; label = "Task Kind"; fieldtype = "Select"; options = $TaskKindOptions.Trim(); in_list_view = 1; in_standard_filter = 1 }
$NextAssignField = [ordered]@{
    dt = "Task"; fieldname = "custom_next_task_assign_to"; label = "Next Task: Assign To"; fieldtype = "Link"; options = "User"; insert_after = "custom_assigned_to"; depends_on = 'eval:["Other: Entry","Other: Processing"].includes(doc.task_kind)'; hidden = 0; reqd = 0
}
$OtherPolicyRoles = @(
    @{ role = "Ops - Order Accepting" },
    @{ role = "Ops - Order Creating" },
    @{ role = "Ops - Inventory" },
    @{ role = "Ops - Returns" },
    @{ role = "Ops - Delivery" },
    @{ role = "Ops - Accounting" },
    @{ role = "Ops - Directors" },
    @{ role = "Ops - Finance" },
    @{ role = "Delivery Driver" }
)

$ClientScriptName = "Task-Other UI Cleanup"
$ClientScript = @'
frappe.ui.form.on("Task", {
    refresh(frm) {
        task_restore_status_priority_complete_all(frm);
        task_other_ui_cleanup(frm);
        setTimeout(function() { task_restore_status_priority_complete_all(frm); task_other_ui_cleanup(frm); }, 200);
        setTimeout(function() { task_restore_status_priority_complete_all(frm); task_other_ui_cleanup(frm); }, 800);
        setTimeout(function() { task_restore_status_priority_complete_all(frm); task_other_ui_cleanup(frm); }, 1600);
        setTimeout(function() { task_restore_status_priority_complete_all(frm); task_other_ui_cleanup(frm); }, 2600);
    },
    task_kind(frm) {
        task_other_ui_cleanup(frm);
    }
});

function task_restore_status_priority_complete_all(frm) {
    if (!frm || frm.doctype !== "Task") return;
    ["status", "priority", "custom_barcode_section"].forEach(function(fieldname) {
        if (frm.fields_dict[fieldname]) frm.toggle_display(fieldname, true);
    });
    var statusField = frm.fields_dict.status;
    if (!statusField || !statusField.$wrapper) return;
    var wrapper = $(frm.wrapper);
    var statusControl = wrapper.find('[data-fieldname="status"]').closest('.frappe-control');
    var priorityControl = wrapper.find('[data-fieldname="priority"]').closest('.frappe-control');
    statusControl.closest('.form-section').show();
    statusControl.closest('.form-column').show();
    priorityControl.closest('.form-section').show();
    priorityControl.closest('.form-column').show();
    statusControl.show();
    priorityControl.show();
    statusField.$wrapper.find("#task-save-btn, #complete-task-btn").show();
    if (frm.is_new() || frm.doc.status === "Completed" || frm.doc.status === "Cancelled" || statusField.$wrapper.find("#complete-task-btn, #other-complete-task-btn").length) return;
    var btn = $('<button id="complete-task-btn" class="btn" style="background-color:#e74c3c;color:#fff;font-weight:bold;font-size:13px;padding:7px 20px;border:none;border-radius:5px;cursor:pointer;margin-top:8px;display:block;">Complete Task</button>');
    btn.on("click", function() {
        if (btn.data("busy")) return;
        var originalStatus = frm.doc.status;
        var originalCompletedOn = frm.doc.completed_on;
        btn.data("busy", true).prop("disabled", true).text("Saving...");
        function resetButton() { btn.data("busy", false).prop("disabled", false).css("background-color", "#e74c3c").text("Complete Task"); }
        frm.save().then(function() {
            btn.text("Completing...");
            frm.set_value("status", "Completed");
            if (!frm.doc.completed_on) frm.set_value("completed_on", frappe.datetime.get_today());
            return frm.save();
        }).then(function() {
            btn.css("background-color", "#27ae60").text("Completed ✓");
            return frm.reload_doc();
        }).catch(function(err) {
            frm.doc.status = originalStatus;
            if (frm.doc.completed_on !== originalCompletedOn) frm.doc.completed_on = originalCompletedOn || "";
            resetButton();
            frappe.show_alert({message: "Failed: " + (err.message || err), indicator: "red"}, 10);
        });
    });
    statusField.$wrapper.append(btn);
}

function task_other_ui_cleanup(frm) {
    if (!frm || frm.doctype !== "Task") return;
    var taskKind = String(frm.doc.task_kind || "").trim();
    var isOther = ["Other: Entry", "Other: Processing"].includes(taskKind);
    if (!isOther) {
        $(frm.wrapper).find('#other-task-photos-box-host').hide();
        return;
    }
    frm.set_df_property("subject", "reqd", 0);
    frm.set_df_property("subject", "label", "Task Name");
    frm.toggle_display("subject", true);
    if (frm.fields_dict.subject && frm.fields_dict.subject.df) frm.fields_dict.subject.df.reqd = 0;
    if (taskKind === "Other: Entry" && (!frm.doc.subject || frm.doc.subject === "New Task" || frm.doc.subject === "Other")) frm.set_value("subject", "Other: Entry");
    if (taskKind === "Other: Processing" && (!frm.doc.subject || frm.doc.subject === "New Task" || frm.doc.subject === "Other")) frm.set_value("subject", "Other: Processing");
    ["status", "priority", "custom_barcode_section"].forEach(function(fieldname) {
        if (frm.fields_dict[fieldname]) frm.toggle_display(fieldname, true);
    });
    if (frm.fields_dict.custom_next_task_assign_to) {
        frm.set_df_property("custom_next_task_assign_to", "label", "Next Task: Assign To");
        frm.toggle_display("custom_next_task_assign_to", taskKind !== "Other: Processing");
    }
    [
        "custom_team_queue_status", "custom_is_team_queue_task", "custom_team_notified",
        "other_items", "other_budget", "other_supplier",
        "warehouse_pickup_photo", "warehouse_dropoff_photo",
        "custom_product_work_section", "custom_task_product_summary", "custom_product_lines",
        "custom_task_add_item_code", "custom_task_add_qty", "custom_task_add_batch_no", "custom_task_add_unit_price",
        "custom_task_scan_barcode", "custom_task_scan_qty", "custom_task_scan_result",
        "custom_product_work_column", "custom_task_product_warning"
    ].forEach(function(fieldname) {
        if (frm.fields_dict[fieldname]) frm.toggle_display(fieldname, false);
    });
    setTimeout(function() {
        var wrapper = $(frm.wrapper);
        wrapper.find('[data-fieldname="custom_product_work_section"]').closest('.form-section').hide();
        wrapper.find('[data-fieldname="custom_task_scan_barcode"], [data-fieldname="custom_task_scan_qty"], [data-fieldname="custom_task_scan_result"], [data-fieldname="custom_product_work_column"], [data-fieldname="custom_task_product_warning"]').closest('.frappe-control').hide();
        wrapper.find('[data-fieldname="other_items"], [data-fieldname="other_budget"], [data-fieldname="other_supplier"], [data-fieldname="warehouse_pickup_photo"], [data-fieldname="warehouse_dropoff_photo"], [data-fieldname="custom_product_lines"]').closest('.frappe-control').hide();
        wrapper.find('.control-label, label').filter(function() { return $.trim($(this).text()) === "Topic"; }).each(function() {
            var control = $(this).closest('.frappe-control');
            if (!control.find('[data-fieldname="subject"]').length && control.attr('data-fieldname') !== 'subject') control.hide();
        });
        wrapper.find('.section-head').filter(function() { return $.trim($(this).text()) === "Products / Dispatch Work"; }).closest('.form-section').hide();
        task_other_force_status_priority_visible(frm);
        task_other_render_photos(frm);
    }, 100);
    task_other_add_accept_button(frm);
    task_other_add_complete_button(frm);
}

function task_other_force_status_priority_visible(frm) {
    task_restore_status_priority_complete_all(frm);
    var wrapper = $(frm.wrapper);
    var sectionControl = wrapper.find('[data-fieldname="custom_barcode_section"]').closest('.frappe-control');
    var statusControl = wrapper.find('[data-fieldname="status"]').closest('.frappe-control');
    var priorityControl = wrapper.find('[data-fieldname="priority"]').closest('.frappe-control');
    var statusSection = sectionControl.closest('.form-section');
    var sectionHead = statusSection.find('.section-head').first();
    var leftColumn = statusSection.find('.form-column').first();
    sectionHead.text('Status and Priority');
    statusSection.find('#other-status-priority-left-host').remove();
    if (leftColumn.length && statusControl.length) {
        statusControl.appendTo(leftColumn);
        if (priorityControl.length) priorityControl.appendTo(leftColumn);
        leftColumn.css({'float':'none','width':'360px','max-width':'100%','margin-left':'0','display':'block'});
    }
    statusSection.show();
    statusControl.show();
    priorityControl.show();
    statusControl.find('#task-save-btn, #complete-task-btn').show();
}

function task_other_add_complete_button(frm) {
    if (!frm || !["Other: Entry", "Other: Processing"].includes(String(frm.doc.task_kind || "").trim())) return;
    task_restore_status_priority_complete_all(frm);
    task_other_force_status_priority_visible(frm);
}

function task_other_add_accept_button(frm) {
    if (!frm || !["Other: Entry", "Other: Processing"].includes(String(frm.doc.task_kind || "").trim())) return;
    if (!["Open", "Working"].includes(frm.doc.status || "Open") || frm.doc.custom_accepted_by === frappe.session.user) return;
    if (frm.page && frm.page.clear_inner_toolbar) frm.page.clear_inner_toolbar();
    frm.add_custom_button(__("Accept / Start Task"), function() {
        var doAccept = function(taskName) {
            frappe.call({ method: "dispatch_task_accept", args: { task_name: taskName }, freeze: true, freeze_message: __("Accepting task..."), callback: function() { frm.reload_doc(); } });
        };
        if (frm.is_new() || frm.dirty()) {
            frm.save().then(function(savedDoc) {
                var realName = (savedDoc && savedDoc.name) || (frm.doc && frm.doc.name) || "";
                if (!realName || realName.indexOf("new-") === 0) { frappe.show_alert({message: __("Task saved. Please click Accept / Start Task again."), indicator: "orange"}, 8); frm.reload_doc(); return; }
                doAccept(realName);
            });
        } else {
            doAccept(frm.doc.name);
        }
    }).addClass("btn-primary");
}

function task_other_render_photos(frm) {
    var taskKind = String(frm.doc.task_kind || "").trim();
    var anchor = taskKind === "Other: Processing" ? (frm.fields_dict.status || frm.fields_dict.priority) : (frm.fields_dict.custom_next_task_assign_to || frm.fields_dict.status || frm.fields_dict.priority);
    if (!anchor || !anchor.$wrapper) return;
    var hosts = $(frm.wrapper).find('#other-task-photos-box-host');
    if (hosts.length > 1) hosts.slice(1).remove();
    var host = $(frm.wrapper).find('#other-task-photos-box-host').first();
    if (!host.length) {
        host = $('<div id="other-task-photos-box-host" class="frappe-control" style="margin-top:12px;margin-bottom:12px;"></div>');
        anchor.$wrapper.after(host);
    }
    host.empty().show();
    frm._other_photo_render_token = (frm._other_photo_render_token || 0) + 1;
    var renderToken = frm._other_photo_render_token;
    var btn = $('<button class="btn btn-sm btn-primary" type="button" style="font-size:12px;padding:5px 14px;background:#000;border-color:#000;color:#fff;border-radius:5px;">+ Add Photos</button>');
    host.append(btn);
    if (frm.is_new() || !frm.doc.name || String(frm.doc.name).indexOf('new-') === 0) {
        host.append('<div style="font-size:11px;color:#8d99a6;margin-top:8px;">Photos will be available after saving this task.</div>');
        btn.on('click', function() { frappe.msgprint(__('Please save the task before adding photos.')); });
        return;
    }
    btn.on('click', function() {
        frappe.call({ method: 'frappe.client.get_list', args: { doctype: 'File', filters: { attached_to_doctype: 'Task', attached_to_name: frm.doc.name }, fields: ['name', 'file_url', 'is_folder'], limit_page_length: 100 }, callback: function(r) {
            var seen = {};
            var images = (r.message || []).filter(function(f) {
                var key = f.file_url || f.name || '';
                if (!key || f.is_folder || seen[key] || !/\.(png|jpe?g|gif|webp|heic|heif)$/i.test(f.file_url || '')) return false;
                seen[key] = true;
                return true;
            });
            if (images.length >= 5) { frappe.msgprint(__('You can attach up to 5 photos.')); return; }
            new frappe.ui.FileUploader({ doctype: 'Task', docname: frm.doc.name, folder: 'Home/Attachments', restrictions: { allowed_file_types: ['image/*'], max_number_of_files: 5 - images.length }, on_success: function() { setTimeout(function() { task_other_render_photos(frm); }, 500); } });
        }});
    });
    frappe.call({ method: 'frappe.client.get_list', args: { doctype: 'File', filters: { attached_to_doctype: 'Task', attached_to_name: frm.doc.name }, fields: ['name', 'file_url', 'file_name', 'is_folder'], limit_page_length: 100 }, callback: function(r) {
        if (renderToken !== frm._other_photo_render_token) return;
        host = $(frm.wrapper).find('#other-task-photos-box-host').first();
        $(frm.wrapper).find('#other-task-photos-box-host').slice(1).remove();
        host.find('.other-task-photo-gallery').remove();
        var seen = {};
        var images = (r.message || []).filter(function(f) {
            var key = f.file_url || f.name || '';
            if (!key || f.is_folder || seen[key] || !/\.(png|jpe?g|gif|webp|heic|heif)$/i.test(f.file_url || '')) return false;
            seen[key] = true;
            return true;
        }).slice(0, 5);
        if (!images.length) return;
        var gallery = $('<div class="other-task-photo-gallery" style="display:flex;gap:8px;flex-wrap:wrap;margin-top:10px;"></div>');
        images.forEach(function(img) { gallery.append('<a href="' + frappe.utils.escape_html(img.file_url) + '" target="_blank"><img src="' + frappe.utils.escape_html(img.file_url) + '" style="width:68px;height:68px;object-fit:cover;border-radius:6px;border:1px solid #d1d8dd;"></a>'); });
        host.append(gallery);
    }});
}
'@

$BeforeSaveName = "Task-Other Entry Default Subject"
$BeforeSaveScript = @'
if doc.get("task_kind") == "Other: Entry":
    if not doc.get("subject") or doc.get("subject") in ("New Task", "Other"):
        doc.subject = "Other: Entry"
elif doc.get("task_kind") == "Other: Processing":
    if not doc.get("subject") or doc.get("subject") in ("New Task", "Other"):
        doc.subject = "Other: Processing"
'@

$AfterSaveName = "Task-after-save-other-processing"
$AfterSaveScript = @'
if doc.get("task_kind") == "Other: Entry" and doc.get("status") == "Completed":
    if not frappe.db.exists("Task", {"task_kind": "Other: Processing", "subject": "Other: Processing", "depends_on_tasks": ["like", "%" + doc.name + "%"]}):
        new_task = frappe.new_doc("Task")
        new_task.subject = "Other: Processing"
        new_task.task_kind = "Other: Processing"
        new_task.status = "Open"
        new_task.priority = doc.get("priority") or "Medium"
        if doc.get("project"):
            new_task.project = doc.project
        if doc.get("customer"):
            new_task.customer = doc.customer
        if doc.get("description"):
            new_task.description = doc.description
        if doc.get("custom_next_task_assign_to"):
            new_task.custom_assigned_to = doc.custom_next_task_assign_to
        elif doc.get("custom_assigned_to"):
            new_task.custom_assigned_to = doc.custom_assigned_to
        new_task.custom_is_team_queue_task = 1
        new_task.custom_team_queue_status = "Open For Team"
        new_task.append("depends_on", {"task": doc.name})
        new_task.flags.ignore_permissions = True
        new_task.insert()
        files = frappe.get_all("File", filters={"attached_to_doctype": "Task", "attached_to_name": doc.name}, fields=["file_url", "file_name", "is_private", "attached_to_field", "folder"])
        for f in files:
            if not f.file_url:
                continue
            if frappe.db.exists("File", {"attached_to_doctype": "Task", "attached_to_name": new_task.name, "file_url": f.file_url}):
                continue
            nf = frappe.new_doc("File")
            nf.file_url = f.file_url
            nf.file_name = f.file_name
            nf.is_private = f.is_private
            nf.folder = f.folder or "Home/Attachments"
            nf.attached_to_doctype = "Task"
            nf.attached_to_name = new_task.name
            nf.attached_to_field = f.attached_to_field
            nf.flags.ignore_permissions = True
            nf.insert()
'@

$ExistingTaskKind = Get-ErpDoc "Custom Field" "Task-task_kind"
$ExistingClient = Get-ErpDoc "Client Script" $ClientScriptName
$ExistingField = Get-ErpDoc "Custom Field" "Task-custom_next_task_assign_to"
$ExistingBefore = Get-ErpDoc "Server Script" $BeforeSaveName
$ExistingAfter = Get-ErpDoc "Server Script" $AfterSaveName
$ExistingEntryPolicy = Get-ErpDoc "Task Access Policy" "Other: Entry"
$ExistingProcessingPolicy = Get-ErpDoc "Task Access Policy" "Other: Processing"
$HasTaskKinds = $ExistingTaskKind -and $ExistingTaskKind.options -match 'Other: Entry' -and $ExistingTaskKind.options -match 'Other: Processing' -and $ExistingTaskKind.options -notmatch "(?m)^Other$"
$HasClient = $ExistingClient -and $ExistingClient.script -match 'task_other_ui_cleanup' -and $ExistingClient.script -match 'task_restore_status_priority_complete_all' -and $ExistingClient.script -match 'Other: Entry' -and $ExistingClient.script -match 'Other: Processing' -and $ExistingClient.script -match 'custom_next_task_assign_to' -and $ExistingClient.script -match 'complete-task-btn' -and $ExistingClient.script -match 'task_other_force_status_priority_visible' -and $ExistingClient.script -match '_other_photo_render_token'
$HasField = $ExistingField -and $ExistingField.label -eq "Next Task: Assign To"
$HasBefore = $ExistingBefore -and $ExistingBefore.script -match 'Other: Entry' -and $ExistingBefore.script -match 'Other: Processing'
$HasAfter = $ExistingAfter -and $ExistingAfter.script -match 'task_kind"\) == "Other: Entry' -and $ExistingAfter.script -match 'new_task.task_kind = "Other: Processing"' -and $ExistingAfter.script -match 'frappe.get_all\("File"'
$HasPolicies = $ExistingEntryPolicy -and $ExistingProcessingPolicy
Write-Host "Task Kind options ready: $(if($HasTaskKinds){'Yes'}else{'No'})"
Write-Host "Client script ready: $(if($HasClient){'Yes'}else{'No'})"
Write-Host "Next assign field ready: $(if($HasField){'Yes'}else{'No'})"
Write-Host "Entry default script ready: $(if($HasBefore){'Yes'}else{'No'})"
Write-Host "Processing creation script ready: $(if($HasAfter){'Yes'}else{'No'})"
Write-Host "Other policies ready: $(if($HasPolicies){'Yes'}else{'No'})"

if ($Mode -eq "Check") {
    if ($HasTaskKinds -and $HasClient -and $HasField -and $HasBefore -and $HasAfter -and $HasPolicies) { Write-Host "Status: fixed" -ForegroundColor Green } else { Write-Host "Status: needs deploy" -ForegroundColor Yellow }
    return
}

$Report = @()
$Report += Upsert-ErpDoc "Custom Field" "Task-task_kind" $TaskKindField
$Report += Upsert-ErpDoc "Custom Field" "Task-custom_next_task_assign_to" $NextAssignField
$Report += Upsert-ErpDoc "Task Access Policy" "Other: Entry" @{ policy_name = "Other: Entry"; allowed_roles = $OtherPolicyRoles }
$Report += Upsert-ErpDoc "Task Access Policy" "Other: Processing" @{ policy_name = "Other: Processing"; allowed_roles = $OtherPolicyRoles }
$Report += Upsert-ErpDoc "Client Script" $ClientScriptName @{ dt = "Task"; view = "Form"; enabled = 1; script = $ClientScript }
$Report += Upsert-ErpDoc "Server Script" $BeforeSaveName @{ script_type = "DocType Event"; reference_doctype = "Task"; doctype_event = "Before Save"; event_frequency = "All"; disabled = 0; script = $BeforeSaveScript }
$Report += Upsert-ErpDoc "Server Script" $AfterSaveName @{ script_type = "DocType Event"; reference_doctype = "Task"; doctype_event = "After Save"; event_frequency = "All"; disabled = 0; script = $AfterSaveScript }
$Report | ConvertTo-Json -Depth 10
Write-Host "Done." -ForegroundColor Green
