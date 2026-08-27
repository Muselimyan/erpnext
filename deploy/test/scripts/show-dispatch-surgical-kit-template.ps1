$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }

function Get-ErpDoc([string]$DocType, [string]$Name) {
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)" -Headers $Headers -Method Get -TimeoutSec 20
}

function Put-ErpDoc([string]$DocType, [string]$Name, [hashtable]$Body) {
    $json = $Body | ConvertTo-Json -Depth 20 -Compress
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 30 | Out-Null
}

$dispatchCase = (Get-ErpDoc -DocType "DocType" -Name "Dispatch Case").data
$field = $dispatchCase.fields | Where-Object { $_.fieldname -eq "surgery_set_type" } | Select-Object -First 1
if (-not $field) {
    throw "Dispatch Case field surgery_set_type was not found; refusing to make broader changes."
}

$field.label = "Item Template"
$field.options = "Collection Set"
Put-ErpDoc -DocType "DocType" -Name "Dispatch Case" -Body @{ fields = $dispatchCase.fields }
Write-Host "Restored Dispatch Case.surgery_set_type label/options." -ForegroundColor Green

$customFieldName = "Dispatch Case-custom_select_surgical_kit_template"
$customFieldBody = @{
    doctype = "Custom Field"
    dt = "Dispatch Case"
    fieldname = "custom_select_surgical_kit_template"
    label = "Select Surgical Kit Template"
    fieldtype = "Link"
    options = "Surgical Kit Template"
    insert_after = "surgery_set_type"
    hidden = 0
    read_only = 0
    reqd = 0
    in_list_view = 0
    in_standard_filter = 0
}

try {
    Get-ErpDoc -DocType "Custom Field" -Name $customFieldName | Out-Null
    Put-ErpDoc -DocType "Custom Field" -Name $customFieldName -Body $customFieldBody
    Write-Host "Updated Custom Field: $customFieldName" -ForegroundColor Green
} catch {
    $json = $customFieldBody | ConvertTo-Json -Depth 20 -Compress
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Custom%20Field" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 30 | Out-Null
    Write-Host "Created Custom Field: $customFieldName" -ForegroundColor Green
}

$script = @'
frappe.ui.form.on("Dispatch Case", {
    custom_select_surgical_kit_template: function(frm) {
        if (!frm.doc.custom_select_surgical_kit_template) {
            return;
        }

        frappe.call({
            method: "frappe.client.get",
            args: {
                doctype: "Surgical Kit Template",
                name: frm.doc.custom_select_surgical_kit_template
            },
            freeze: true,
            freeze_message: __("Loading surgical kit template..."),
            callback: function(r) {
                var template = r.message;
                var items = template && template.template_items ? template.template_items : [];

                if (!items.length) {
                    frappe.msgprint(__("Selected Surgical Kit Template has no items."));
                    return;
                }

                frm.clear_table("case_items");

                items.forEach(function(item) {
                    var row = frm.add_child("case_items");
                    row.item_code = item.item_code;
                    row.item_name = item.item_name;
                    row.dispatched_qty = item.qty || 1;
                });

                frm.refresh_field("case_items");
                frappe.show_alert({
                    message: __("Loaded {0} items from Surgical Kit Template", [items.length]),
                    indicator: "green"
                });
            }
        });
    }
});
'@

$body = @{
    doctype = "Client Script"
    name = "Dispatch Case-Template Auto Fill"
    dt = "Dispatch Case"
    view = "Form"
    enabled = 1
    script = $script
}

Put-ErpDoc -DocType "Client Script" -Name "Dispatch Case-Template Auto Fill" -Body $body
Write-Host "Updated Client Script: Dispatch Case-Template Auto Fill." -ForegroundColor Green

try {
    Invoke-RestMethod -Uri "$BaseUrl/api/method/frappe.clear_cache" -Headers $Headers -Method Post -TimeoutSec 30 | Out-Null
    Write-Host "Cache cleared." -ForegroundColor Green
} catch {
    Write-Host "Cache clear failed/non-critical: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "Done. Hard refresh ERPNext and open Dispatch Case." -ForegroundColor Green
