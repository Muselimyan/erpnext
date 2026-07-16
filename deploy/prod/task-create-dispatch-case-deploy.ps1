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

$CreateApi = @'
def run_script():
    task_name = frappe.form_dict.get("task_name")
    if not task_name:
        frappe.throw("Task is required.")
    task = frappe.get_doc("Task", task_name)
    if task.get("dispatch_case"):
        frappe.response["message"] = {"ok": True, "dispatch_case": task.dispatch_case, "created": False}
        return
    if not task.get("customer"):
        frappe.throw("Select Customer on the Task before creating Dispatch Case / Packing Items.")
    customer = task.customer
    case = frappe.new_doc("Dispatch Case")
    case.customer = customer
    case.status = "Draft"
    if task.get("description"):
        case.notes = "Created from Task " + task.name + "\n\n" + task.description
    else:
        case.notes = "Created from Task " + task.name
    case.flags.ignore_permissions = True
    case.insert()
    task.dispatch_case = case.name
    task.flags.ignore_permissions = True
    task.save()
    frappe.response["message"] = {"ok": True, "dispatch_case": case.name, "created": True}
run_script()
'@

$ClientScript = @'
frappe.ui.form.on("Task", {
    refresh(frm) {
        const dispatchKinds = [
            "Pack / prepare items", "Dispatch picking / hand-off", "Delivery",
            "Pickup Returns", "Return drop-off at warehouse", "Returns processing / verification",
            "Returns restocking", "Invoice preparation / create invoice", "Debt Collection", "Discount Approval"
        ];
        const isDispatchWork = frm.doc.dispatch_case || dispatchKinds.includes(frm.doc.task_kind);
        if (!frm.is_new() && isDispatchWork) {
            if (frm.doc.dispatch_case) {
                frm.add_custom_button(__("Open Dispatch Case / Items"), function() {
                    frappe.set_route("Form", "Dispatch Case", frm.doc.dispatch_case);
                }, __("Dispatch & Packing Work"));
            } else {
                frm.dashboard.add_comment(
                    __("This task needs a <b>Dispatch Case / Packing Items</b> document before item rows, scanning, batch/LOT, expiry, and missing quantities can be managed."),
                    "orange",
                    true
                );
                frm.add_custom_button(__("Create Dispatch Case / Items"), function() {
                    if (!frm.doc.customer) {
                        frappe.msgprint(__("Select Customer on this Task first."));
                        return;
                    }
                    frappe.call({
                        method: "task_create_dispatch_case",
                        args: { task_name: frm.doc.name },
                        freeze: true,
                        freeze_message: __("Creating Dispatch Case / Packing Items..."),
                        callback: function(r) {
                            const msg = r.message || {};
                            if (msg.dispatch_case) {
                                frappe.show_alert({ message: __("Dispatch Case linked"), indicator: "green" });
                                frappe.set_route("Form", "Dispatch Case", msg.dispatch_case);
                            } else {
                                frm.reload_doc();
                            }
                        }
                    });
                }, __("Dispatch & Packing Work"));
            }
        }
    }
});
'@

$ServerName = "task_create_dispatch_case"
$ClientName = "Task-Create Dispatch Case Items"
$Report=[ordered]@{mode=$Mode;server_scripts=@();client_scripts=@();notes=@()}
$E=Get-ErpDoc "Server Script" $ServerName
if($Mode -eq "Deploy"){
    $Report.server_scripts += Upsert-ErpDoc "Server Script" $ServerName ([ordered]@{script_type="API";api_method="task_create_dispatch_case";allow_guest=0;disabled=0;enable_rate_limit=0;script=$CreateApi})
} else { $Report.server_scripts += [pscustomobject]@{name=$ServerName;exists=($null -ne $E)} }
$E=Get-ErpDoc "Client Script" $ClientName
if($Mode -eq "Deploy"){
    $Report.client_scripts += Upsert-ErpDoc "Client Script" $ClientName ([ordered]@{dt="Task";view="Form";enabled=1;script=$ClientScript})
} else { $Report.client_scripts += [pscustomobject]@{name=$ClientName;exists=($null -ne $E)} }
$Report.notes += "Adds Task button to create/link Dispatch Case / Packing Items for dispatch-related manual tasks. Does not duplicate item rows into Task."
$Report | ConvertTo-Json -Depth 30
