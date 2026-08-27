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

$PropertySetters = @(
    [pscustomobject]@{name="Task-dispatch_case-label";doc_type="Task";field_name="dispatch_case";property="label";property_type="Data";value="Dispatch Case / Packing Items"},
    [pscustomobject]@{name="Task-dispatch_case-description";doc_type="Task";field_name="dispatch_case";property="description";property_type="Small Text";value="Open this Dispatch Case to view product rows, quantities, batch/LOT, expiry, scanned qty, missing qty, FEFO warnings, and packing problems."},
    [pscustomobject]@{name="Task-dispatch_case-bold";doc_type="Task";field_name="dispatch_case";property="bold";property_type="Check";value="1"},
    [pscustomobject]@{name="Task-dispatch_case-in_list_view";doc_type="Task";field_name="dispatch_case";property="in_list_view";property_type="Check";value="1"}
)

$TaskClientScript = @'
frappe.ui.form.on("Task", {
    refresh(frm) {
        if (frm.doc.dispatch_case) {
            frm.dashboard.add_comment(
                __("This task uses item rows from <b>Dispatch Case / Packing Items</b>. Open it to view quantities, batch/LOT, expiry, scanned and missing items."),
                "blue",
                true
            );
            frm.add_custom_button(__("Open Dispatch Case / Items"), function() {
                frappe.set_route("Form", "Dispatch Case", frm.doc.dispatch_case);
            }, __("Dispatch & Packing Work"));
        }
        if (!frm.is_new() && frm.doc.custom_is_team_queue_task && frm.doc.custom_team_queue_status === "Open For Team") {
            frm.add_custom_button(__("Accept / Start Task"), function() {
                frappe.call({ method: "dispatch_task_accept", args: { task_name: frm.doc.name }, freeze: true, callback: function() { frm.reload_doc(); } });
            }, __("Dispatch & Packing Work"));
        }
    }
});

frappe.listview_settings["Task"] = frappe.listview_settings["Task"] || {};
frappe.listview_settings["Task"].onload = function(listview) {
    listview.page.add_inner_button(__("My Team Queue"), function() {
        listview.filter_area.clear();
        listview.filter_area.add([["Task", "custom_is_team_queue_task", "=", 1]]);
        listview.filter_area.add([["Task", "custom_team_queue_status", "=", "Open For Team"]]);
        listview.refresh();
    });
};
'@

$Report=[ordered]@{mode=$Mode;property_setters=@();client_scripts=@();notes=@()}
foreach($p in $PropertySetters){
    $E=Get-ErpDoc "Property Setter" $p.name
    if($Mode -eq "Deploy"){
        $Body=[ordered]@{doc_type=$p.doc_type;doctype_or_field="DocField";field_name=$p.field_name;property=$p.property;property_type=$p.property_type;value=$p.value}
        $Report.property_setters += Upsert-ErpDoc "Property Setter" $p.name $Body
    } else { $Report.property_setters += [pscustomobject]@{name=$p.name;exists=($null -ne $E)} }
}
$CsName = "Task-Dispatch Packing Usability"
$E=Get-ErpDoc "Client Script" $CsName
if($Mode -eq "Deploy"){
    $Report.client_scripts += Upsert-ErpDoc "Client Script" $CsName ([ordered]@{dt="Task";view="Form";enabled=1;script=$TaskClientScript})
} else { $Report.client_scripts += [pscustomobject]@{name=$CsName;exists=($null -ne $E)} }
$Report.notes += "Adds clear Task label, help text, dashboard guidance, and Open Dispatch Case / Items button. Does not duplicate item rows into Task."
$Report | ConvertTo-Json -Depth 30
