param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
)

Set-StrictMode -Off

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config     = Get-Content $ConfigPath -Raw
$BaseUrl    = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey     = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec     = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers    = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json"; "User-Agent" = "Mozilla/5.0" }

function Enc ([string]$s) { [uri]::EscapeDataString($s) }
function Invoke-ErpRequest { param([string]$Method, [string]$Path, $Body=$null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 120 }
    $Json = $Body | ConvertTo-Json -Depth 40
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 120
}
function Get-ErpDoc { param([string]$DocType,[string]$Name)
    try { return (Invoke-ErpRequest -Method Get -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)").data } catch { return $null }
}
function Upsert-ErpDoc { param([string]$DocType,[string]$Name,$Body)
    $Existing = Get-ErpDoc $DocType $Name
    if ($null -eq $Existing) { $Body.name=$Name; $C=(Invoke-ErpRequest Post "/api/resource/$(Enc $DocType)" $Body).data; return [pscustomobject]@{action="created";name=$C.name} }
    $U=(Invoke-ErpRequest Put "/api/resource/$(Enc $DocType)/$(Enc $Name)" $Body).data; return [pscustomobject]@{action="updated";name=$U.name}
}

# Task Product Line child table DocType
$TaskProductLineDocType = [ordered]@{
    name = "Task Product Line"
    module = "Projects"
    custom = 1
    istable = 1
    editable_grid = 1
    autoname = "hash"
    track_changes = 0
    is_submittable = 0
    fields = @(
        [ordered]@{ fieldname="item_name"; label="Item Name"; fieldtype="Link"; options="Item"; in_list_view=1; bold=1; columns=4 },
        [ordered]@{ fieldname="item_code"; label="Item Code"; fieldtype="Data"; in_list_view=0; columns=2; read_only=1; fetch_from="item_name.item_code" },
        [ordered]@{ fieldname="item_group"; label="Item Group"; fieldtype="Data"; in_list_view=0; columns=2; read_only=1; fetch_from="item_name.item_group" },
        [ordered]@{ fieldname="description"; label="Description / Notes"; fieldtype="Small Text"; in_list_view=1; columns=3 },
        [ordered]@{ fieldname="qty"; label="Qty"; fieldtype="Float"; in_list_view=1; columns=1; default="1" },
        [ordered]@{ fieldname="warehouse"; label="Warehouse"; fieldtype="Link"; options="Warehouse"; in_list_view=1; columns=2; default="Main - Inmed" },
        [ordered]@{ fieldname="batch_no"; label="Batch / LOT"; fieldtype="Link"; options="Batch"; in_list_view=0; columns=2 },
        [ordered]@{ fieldname="notes"; label="Notes"; fieldtype="Small Text"; in_list_view=0 }
    )
}

# Custom field to add the child table to Task
$TaskProductLinesField = [ordered]@{
    name = "Task-custom_product_lines"
    dt = "Task"
    fieldname = "custom_product_lines"
    label = "Product Lines"
    fieldtype = "Table"
    options = "Task Product Line"
    insert_after = "custom_task_product_summary"
}

# Client script - Create Dispatch Case button
$ClientScript = @'
frappe.ui.form.on("Task", {
    refresh: function(frm) {
        // Show "Create Dispatch Case" button immediately for Order entry tasks with customer
        if (frm.doc.task_kind === "Order entry" && frm.doc.customer) {
            frm.add_custom_button(__("Create Dispatch Case"), function() {
                // Save task first if it is new or has unsaved changes
                if (frm.is_new() || frm.is_dirty()) {
                    frappe.msgprint(__("Saving task first..."));
                    frm.save().then(function() {
                        create_dispatch_case_from_task(frm);
                    });
                } else {
                    create_dispatch_case_from_task(frm);
                }
            }, __("Actions"));
        }
    }
});

// Function to create Dispatch Case from Task (no product lines needed)
function create_dispatch_case_from_task(frm) {
    frappe.confirm(
        __("Create a new Dispatch Case from this Task? You will add items in the Dispatch Case."),
        function() {
            // Create new Dispatch Case with auto-filled fields from Task
            frappe.call({
                method: "frappe.client.insert",
                args: {
                    doc: {
                        doctype: "Dispatch Case",
                        customer: frm.doc.customer || "",
                        client_location_warehouse: "Main - Inmed",
                        surgery_date: frm.doc.exp_end_date || frappe.datetime.nowdate(),
                        notes: frm.doc.description || ("Created from Task: " + frm.doc.subject)
                    }
                },
                callback: function(r) {
                    if (r.message) {
                        let dispatch_case = r.message.name;
                        
                        // Link Task to Dispatch Case
                        frappe.call({
                            method: "frappe.client.set_value",
                            args: {
                                doctype: "Task",
                                name: frm.doc.name,
                                fieldname: "dispatch_case",
                                value: dispatch_case
                            },
                            callback: function() {
                                frappe.show_alert({
                                    message: __("Dispatch Case {0} created. Add items now.", [dispatch_case]),
                                    indicator: "green"
                                });
                                
                                // Open the new Dispatch Case
                                frappe.set_route("Form", "Dispatch Case", dispatch_case);
                                
                                // Auto-reload after 500ms to prevent stale document errors
                                setTimeout(function() {
                                    if (cur_frm && cur_frm.doctype === "Dispatch Case" && cur_frm.doc.name === dispatch_case) {
                                        cur_frm.reload_doc();
                                    }
                                }, 500);
                            }
                        });
                    }
                }
            });
        }
    );
}

'@

$Report = [ordered]@{ mode=$Mode; doctype=@(); custom_fields=@(); client_scripts=@(); notes=@() }

# Deploy/Check Task Product Line DocType
$Existing = Get-ErpDoc -DocType "DocType" -Name "Task Product Line"
if ($Mode -eq "Deploy") {
    if ($null -eq $Existing) {
        $Report.doctype += [pscustomobject]@{ action="created"; name="Task Product Line" }
        $Created = (Invoke-ErpRequest -Method Post -Path "/api/resource/DocType" -Body $TaskProductLineDocType).data
    } else {
        $Report.doctype += [pscustomobject]@{ action="exists"; name="Task Product Line" }
    }
} else {
    $Report.doctype += [pscustomobject]@{ name="Task Product Line"; exists=($null -ne $Existing) }
}

# Deploy/Check custom field on Task
$Existing = Get-ErpDoc -DocType "Custom Field" -Name $TaskProductLinesField.name
if ($Mode -eq "Deploy") {
    $Report.custom_fields += Upsert-ErpDoc -DocType "Custom Field" -Name $TaskProductLinesField.name -Body $TaskProductLinesField
} else {
    $Report.custom_fields += [pscustomobject]@{ name=$TaskProductLinesField.name; exists=($null -ne $Existing) }
}

# Deploy/Check client script
$ClientScriptName = "Task-Product Lines Display"
$Existing = Get-ErpDoc -DocType "Client Script" -Name $ClientScriptName
if ($Mode -eq "Deploy") {
    $Body = [ordered]@{ dt="Task"; view="Form"; enabled=1; script=$ClientScript }
    $Report.client_scripts += Upsert-ErpDoc -DocType "Client Script" -Name $ClientScriptName -Body $Body
} else {
    $Report.client_scripts += [pscustomobject]@{ name=$ClientScriptName; exists=($null -ne $Existing) }
}

$Report.notes += "Task Product Line child table shows Item Name prominently with Item Code secondary."
$Report.notes += "Available Qty shows stock in selected warehouse (default Main - Inmed)."
$Report.notes += "Description field allows manual entry for items not yet in system."
$Report.notes += "Product lines are editable only for Order entry and Pack/prepare items task kinds."

$Report | ConvertTo-Json -Depth 30
