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

Write-Host "=== Dispatch Case - Add Products Button ===" -ForegroundColor Cyan

$ClientScriptName = "Dispatch Case-Products Button"
$ClientScriptBody = @'
frappe.ui.form.on("Dispatch Case", {
    refresh: function(frm) {
        // Add "Products" button to select items by category
        if (!frm.is_new()) {
            frm.add_custom_button(__("Add Items by Category"), function() {
                let last_loaded_group = null;
                let d = new frappe.ui.Dialog({
                    title: __("Select Items from Category"),
                    size: "large",
                    fields: [
                        {
                            fieldname: "item_group",
                            label: __("Item Group / Category"),
                            fieldtype: "Link",
                            options: "Item Group",
                            reqd: 1,
                            onchange: function() {
                                let group = d.get_value("item_group");
                                if (group && group !== last_loaded_group) {
                                    last_loaded_group = group;
                                    d.fields_dict.items_html.$wrapper.html("<p class='text-muted'>Loading items...</p>");
                                    
                                    frappe.call({
                                        method: "frappe.client.get_list",
                                        args: {
                                            doctype: "Item",
                                            filters: { item_group: group },
                                            fields: ["name", "item_name", "item_group", "standard_rate"],
                                            limit_page_length: 500
                                        },
                                        callback: function(r) {
                                            if (r.message && r.message.length > 0) {
                                                let html = "<div style='max-height: 400px; overflow-y: auto;'>";
                                                html += "<table class='table table-bordered table-hover'>";
                                                html += "<thead><tr><th width='5%'></th><th>Item Name</th><th>Item Code</th><th>Price</th></tr></thead>";
                                                html += "<tbody>";
                                                r.message.forEach(function(item) {
                                                    let price = item.standard_rate ? frappe.format(item.standard_rate, {fieldtype: "Currency"}) : "-";
                                                    html += "<tr>";
                                                    html += "<td><input type='checkbox' class='item-checkbox' data-item='" + item.name + "' data-item-name='" + (item.item_name || item.name) + "' data-price='" + (item.standard_rate || 0) + "'></td>";
                                                    html += "<td>" + (item.item_name || item.name) + "</td>";
                                                    html += "<td><small>" + item.name + "</small></td>";
                                                    html += "<td>" + price + "</td>";
                                                    html += "</tr>";
                                                });
                                                html += "</tbody></table></div>";
                                                html += "<p class='text-muted' style='margin-top: 10px;'>Found " + r.message.length + " items</p>";
                                                d.fields_dict.items_html.$wrapper.html(html);
                                            } else {
                                                d.fields_dict.items_html.$wrapper.html("<p class='text-muted'>No items found in category: <strong>" + group + "</strong></p>");
                                            }
                                        },
                                        error: function(r) {
                                            d.fields_dict.items_html.$wrapper.html("<p class='text-danger'>Error loading items: " + (r.message || "Unknown error") + "</p>");
                                            console.error("Error loading items for group:", group, r);
                                        }
                                    });
                                }
                            }
                        },
                        {
                            fieldname: "items_html",
                            fieldtype: "HTML"
                        }
                    ],
                    primary_action_label: __("Add Selected Items"),
                    primary_action: function(values) {
                        let selected = [];
                        d.$wrapper.find(".item-checkbox:checked").each(function() {
                            selected.push({
                                item_code: $(this).data("item"),
                                item_name: $(this).data("item-name"),
                                price: $(this).data("price")
                            });
                        });
                        
                        if (selected.length === 0) {
                            frappe.msgprint(__("Please select at least one item"));
                            return;
                        }
                        
                        // Add items to case_items child table
                        selected.forEach(function(item) {
                            let row = frm.add_child("case_items");
                            row.item_code = item.item_code;
                            row.item_name = item.item_name;
                            row.dispatched_qty = 1;
                            row.unit_price = item.price || 0;
                        });
                        
                        frm.refresh_field("case_items");
                        frappe.show_alert({
                            message: __("Added {0} item(s)", [selected.length]), 
                            indicator: "green"
                        });
                        d.hide();
                    }
                });
                d.show();
            }, __("Actions"));
        }
    }
});
'@

$ScriptDef = [ordered]@{
    name = $ClientScriptName
    dt = "Dispatch Case"
    enabled = 1
    script_type = "Form"
    script = $ClientScriptBody
}

if ($Mode -eq "Deploy") {
    try {
        $Result = Upsert-ErpDoc -DocType "Client Script" -Name $ClientScriptName -Body $ScriptDef
        Write-Host "Client Script: $($Result.action)" -ForegroundColor Green
        
        [ordered]@{
            mode = "Deploy"
            client_script = $Result
        } | ConvertTo-Json -Depth 10
    } catch {
        Write-Host "ERROR: $_" -ForegroundColor Red
        throw
    }
} else {
    $Existing = Get-ErpDoc -DocType "Client Script" -Name $ClientScriptName
    [ordered]@{
        mode = "Check"
        client_script = [ordered]@{
            name = $ClientScriptName
            exists = ($null -ne $Existing)
        }
    } | ConvertTo-Json -Depth 10
}

Write-Host "`nDone! The 'Add Items by Category' button will appear in Dispatch Case Actions menu." -ForegroundColor Cyan
Write-Host "It will add items to the Case Items table with quantity 1 and standard price." -ForegroundColor White
