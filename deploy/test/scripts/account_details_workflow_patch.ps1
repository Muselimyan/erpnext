$ErrorActionPreference = "Stop"

$BaseUrl = "https://test.erpnext.am"
$ApiKey  = "af78cbd691f0b2e"
$ApiSec  = "b26698573b80f5e"
$H       = @{ Authorization = "token ${ApiKey}:${ApiSec}"; "Content-Type" = "application/json" }

function Enc([string]$s) { [uri]::EscapeDataString($s) }

function Invoke-ApiJson {
    param(
        [string]$Method,
        [string]$Url,
        $Body = $null
    )
    $params = @{
        Uri        = $Url
        Method     = $Method
        Headers    = $H
        TimeoutSec = 60
    }
    if ($null -ne $Body) {
        $params.Body = ($Body | ConvertTo-Json -Depth 20)
    }
    return Invoke-RestMethod @params
}

function Get-Doc {
    param([string]$Doctype, [string]$Name)
    $url = "$BaseUrl/api/resource/$(Enc $Doctype)/$(Enc $Name)"
    return (Invoke-ApiJson -Method Get -Url $url).data
}

function Put-Doc {
    param([string]$Doctype, [string]$Name, $Body)
    $url = "$BaseUrl/api/resource/$(Enc $Doctype)/$(Enc $Name)"
    return (Invoke-ApiJson -Method Put -Url $url -Body $Body).data
}

function New-Doc {
    param([string]$Doctype, $Body)
    $url = "$BaseUrl/api/resource/$(Enc $Doctype)"
    return (Invoke-ApiJson -Method Post -Url $url -Body $Body).data
}

function Ensure-CustomField {
    param($FieldDoc)
    $name = $FieldDoc.name
    try {
        $existing = Get-Doc "Custom Field" $name
        $body = @{}
        foreach ($p in $FieldDoc.Keys) { if ($p -ne "doctype" -and $p -ne "name") { $body[$p] = $FieldDoc[$p] } }
        Put-Doc "Custom Field" $name $body | Out-Null
        Write-Host "Updated Custom Field: $name" -ForegroundColor Green
    } catch {
        New-Doc "Custom Field" $FieldDoc | Out-Null
        Write-Host "Created Custom Field: $name" -ForegroundColor Green
    }
}

function Upsert-ServerScript {
    param($ScriptDoc)
    $name = $ScriptDoc.name
    try {
        Get-Doc "Server Script" $name | Out-Null
        $body = @{}
        foreach ($p in $ScriptDoc.Keys) { if ($p -ne "doctype" -and $p -ne "name") { $body[$p] = $ScriptDoc[$p] } }
        Put-Doc "Server Script" $name $body | Out-Null
        Write-Host "Updated Server Script: $name" -ForegroundColor Green
    } catch {
        New-Doc "Server Script" $ScriptDoc | Out-Null
        Write-Host "Created Server Script: $name" -ForegroundColor Green
    }
}

Write-Host "Applying Account Details workflow patch to TEST only: $BaseUrl" -ForegroundColor Cyan

$taskKind = Get-Doc "Custom Field" "Task-task_kind"
$options = @($taskKind.options -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -ne "Account details" -and $_ -ne "Account Details: Entry" -and $_ -ne "Account Details: Processing" })
$insertAfter = "Write-off Approval"
$newOptions = New-Object System.Collections.Generic.List[string]
foreach ($opt in $options) {
    $newOptions.Add($opt)
    if ($opt -eq $insertAfter) {
        $newOptions.Add("Account Details: Entry")
        $newOptions.Add("Account Details: Processing")
    }
}
if (-not $newOptions.Contains("Account Details: Entry")) { $newOptions.Add("Account Details: Entry") }
if (-not $newOptions.Contains("Account Details: Processing")) { $newOptions.Add("Account Details: Processing") }
Put-Doc "Custom Field" "Task-task_kind" @{ options = ($newOptions -join "`n") } | Out-Null
Write-Host "Updated Task Kind options" -ForegroundColor Green

Ensure-CustomField @{
    doctype = "Custom Field"
    name = "Task-custom_account_details_entry_task"
    dt = "Task"
    fieldname = "custom_account_details_entry_task"
    label = "Account Details Entry Task"
    fieldtype = "Link"
    options = "Task"
    insert_after = "custom_next_task_assign_to"
    hidden = 1
    read_only = 1
}

$defaultScript = Get-Doc "Server Script" "Task-Account Details Default Assignment"
$defaultText = [string]$defaultScript.script
$defaultText = $defaultText.Replace('doc.get("task_kind") == "Account details"', 'doc.get("task_kind") == "Account Details: Entry"')
$defaultText = $defaultText.Replace('doc.subject = "Account details"', 'doc.subject = "Account Details: Entry"')
$defaultText = $defaultText.Replace('"accounting.team@example.com"', '"accounting.team@example.com"')
Put-Doc "Server Script" "Task-Account Details Default Assignment" @{ script = $defaultText } | Out-Null
Write-Host "Updated Account Details default assignment script" -ForegroundColor Green

$policy = Get-Doc "Server Script" "Task-before-save-policy"
$policyText = [string]$policy.script
$policyReplacement = "`"Account Details: Entry`": [`"Ops - Accounting`", `"Ops - Finance`", `"Ops - Directors`"],`n    `"Account Details: Processing`": [`"Ops - Accounting`", `"Ops - Finance`", `"Ops - Directors`"],"
$policyText = $policyText.Replace('"Account details": ["Ops - Accounting", "Ops - Finance", "Ops - Directors"],', $policyReplacement)
$policyText = $policyText.Replace('"Account details"', '"Account Details: Entry"')
Put-Doc "Server Script" "Task-before-save-policy" @{ script = $policyText } | Out-Null
Write-Host "Updated Task policy script" -ForegroundColor Green

$processingScript = @'
if doc.get("task_kind") == "Account Details: Entry":
    before = doc.get_doc_before_save()
    before_status = None
    if before:
        before_status = before.status

    if doc.status == "Completed" and before_status != "Completed":
        existing = frappe.db.exists("Task", {"custom_account_details_entry_task": doc.name})
        if not existing:
            assignee = doc.get("custom_next_task_assign_to")
            if not assignee:
                assignee = "accounting.team@example.com"

            new_task = frappe.new_doc("Task")
            new_task.subject = doc.subject or "Account Details: Processing"
            new_task.task_kind = "Account Details: Processing"
            new_task.task_access_policy = "Account Details: Processing"
            new_task.status = "Open"
            new_task.description = doc.description
            new_task.priority = doc.priority
            new_task.customer = doc.customer
            new_task.exp_start_date = doc.exp_start_date
            new_task.exp_end_date = doc.exp_end_date
            new_task.expected_time = doc.expected_time
            new_task.custom_assigned_to = assignee
            new_task.custom_account_details_entry_task = doc.name

            if doc.get("custom_account_photos"):
                for row in doc.get("custom_account_photos"):
                    new_task.append("custom_account_photos", row.as_dict())

            new_task.flags.ignore_permissions = True
            new_task.insert()

            frappe.db.set_value("Task", new_task.name, "_assign", json.dumps([assignee]))
            todo = frappe.new_doc("ToDo")
            todo.status = "Open"
            todo.allocated_to = assignee
            todo.reference_type = "Task"
            todo.reference_name = new_task.name
            todo.description = new_task.subject or new_task.name
            todo.assigned_by = frappe.session.user
            todo.flags.ignore_permissions = True
            todo.insert()

            files = frappe.get_all("File", filters={"attached_to_doctype": "Task", "attached_to_name": doc.name}, fields=["file_url", "file_name", "is_private", "attached_to_field"])
            for f in files:
                nf = frappe.new_doc("File")
                nf.file_url = f.file_url
                nf.file_name = f.file_name
                nf.is_private = f.is_private
                nf.attached_to_doctype = "Task"
                nf.attached_to_name = new_task.name
                nf.attached_to_field = f.attached_to_field
                nf.flags.ignore_permissions = True
                nf.insert()
'@

Upsert-ServerScript @{
    doctype = "Server Script"
    name = "Task-after-save-account-details-processing"
    script_type = "DocType Event"
    reference_doctype = "Task"
    doctype_event = "After Save"
    disabled = 0
    script = $processingScript
}

Write-Host "Patch complete on TEST. No Task deletion was performed." -ForegroundColor Cyan
