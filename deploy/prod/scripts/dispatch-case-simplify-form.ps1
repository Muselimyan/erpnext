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

# Client script to hide unnecessary sections from Order Creation team
$DispatchCaseSimplifyScript = @'
frappe.ui.form.on("Dispatch Case", {
    refresh(frm) {
        // Only simplify for Order Creation team
        const order_creation_roles = ["Ops - Order Creating"];
        const user_roles = frappe.user_roles || [];
        const is_order_creation = order_creation_roles.some(role => user_roles.includes(role));
        
        // Don't hide for financial/director roles
        const privileged_roles = ["Ops - Accounting", "Ops - Finance", "Ops - Directors", "System Manager"];
        const is_privileged = privileged_roles.some(role => user_roles.includes(role));
        
        if (is_order_creation && !is_privileged) {
            // Hide Linked Tasks section
            if (frm.fields_dict.tasks_section) {
                frm.fields_dict.tasks_section.df.hidden = 1;
                frm.refresh_field("tasks_section");
            }
            
            // Hide all task link fields
            const task_fields = [
                "order_entry_task", "discount_approval_task", "discount_approval_status",
                "pack_task", "delivery_task", "return_waiting_task", "return_pickup_task",
                "returns_inspection_task", "restock_task", "invoice_task"
            ];
            task_fields.forEach(function(fieldname) {
                if (frm.fields_dict[fieldname]) {
                    frm.set_df_property(fieldname, "hidden", 1);
                }
            });
            
            // Hide Stock Entries section
            if (frm.fields_dict.se_section) {
                frm.fields_dict.se_section.df.hidden = 1;
                frm.refresh_field("se_section");
            }
            
            // Hide all stock entry fields
            const se_fields = [
                "dispatch_stock_entry", "delivery_stock_entry", "consumption_stock_entry",
                "return_pickup_stock_entry", "return_receive_stock_entry", "restock_stock_entry"
            ];
            se_fields.forEach(function(fieldname) {
                if (frm.fields_dict[fieldname]) {
                    frm.set_df_property(fieldname, "hidden", 1);
                }
            });
            
            // Hide Photos section
            if (frm.fields_dict.photo_section) {
                frm.fields_dict.photo_section.df.hidden = 1;
                frm.refresh_field("photo_section");
            }
            
            // Hide photo fields
            const photo_fields = ["delivery_photo", "return_dropoff_photo"];
            photo_fields.forEach(function(fieldname) {
                if (frm.fields_dict[fieldname]) {
                    frm.set_df_property(fieldname, "hidden", 1);
                }
            });
            
            // Hide packing scan fields (these are custom fields)
            const packing_fields = [
                "custom_packing_scan_barcode", "custom_packing_scan_qty", 
                "custom_packing_scan_result", "custom_packing_last_warning",
                "custom_packing_problem_status", "custom_packing_problem_summary",
                "custom_problem_alert_sent"
            ];
            packing_fields.forEach(function(fieldname) {
                if (frm.fields_dict[fieldname]) {
                    frm.set_df_property(fieldname, "hidden", 1);
                }
            });
            
            // Hide packing-related columns in case_items table
            if (frm.fields_dict.case_items && frm.fields_dict.case_items.grid) {
                const grid = frm.fields_dict.case_items.grid;
                
                if (grid.docfields) {
                    const hide_columns = [
                        "custom_packing_status", "custom_scanned_qty", "custom_remaining_qty",
                        "custom_last_scanned_barcode", "custom_last_scan_at", "custom_last_scanned_by",
                        "custom_fefo_warning", "custom_scan_note", "custom_problem_reason",
                        "custom_problem_alert_sent", "returned_qty", "lost_damaged_qty", "used_qty"
                    ];
                    
                    grid.docfields.forEach(function(df) {
                        if (hide_columns.includes(df.fieldname)) {
                            df.hidden = 1;
                            df.in_list_view = 0;
                        }
                    });
                }
                
                grid.refresh();
            }
            
            // Show a helpful message
            if (frm.is_new()) {
                frappe.show_alert({
                    message: __("Form simplified for Order Creation. Fill in Return Expected, verify items, and Submit!"),
                    indicator: "blue"
                });
            }
        }
    }
});
'@

$Report = [ordered]@{ mode=$Mode; client_scripts=@() }

# Deploy/Check client script
$ClientScriptName = "Dispatch Case-Simplify for Order Creation"
$ClientScriptBody = [ordered]@{
    name = $ClientScriptName
    dt = "Dispatch Case"
    view = "Form"
    enabled = 1
    script = $DispatchCaseSimplifyScript
}

$Existing = Get-ErpDoc -DocType "Client Script" -Name $ClientScriptName
if ($Mode -eq "Deploy") {
    $Report.client_scripts += Upsert-ErpDoc -DocType "Client Script" -Name $ClientScriptName -Body $ClientScriptBody
} else {
    $Report.client_scripts += [pscustomobject]@{ name=$ClientScriptName; exists=($null -ne $Existing) }
}

$Report | ConvertTo-Json -Depth 10
