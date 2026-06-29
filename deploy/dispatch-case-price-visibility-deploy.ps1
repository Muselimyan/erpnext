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

# Client script to hide price/discount fields and Invoice/Payment section based on user roles
$DispatchCasePriceVisibilityScript = @'
frappe.ui.form.on("Dispatch Case", {
    refresh(frm) {
        // Roles that can see prices and financial info
        const financial_roles = ["Ops - Accounting", "Ops - Finance", "Ops - Directors", "System Manager"];
        const user_roles = frappe.user_roles || [];
        const has_financial_access = financial_roles.some(role => user_roles.includes(role));
        
        if (!has_financial_access) {
            // Hide Invoice and Payment section
            if (frm.fields_dict.payment_section) {
                frm.fields_dict.payment_section.df.hidden = 1;
                frm.refresh_field("payment_section");
            }
            
            // Hide all fields in payment section
            const payment_fields = [
                "sales_invoice", "prepaid_amount", "prepaid_payment_entry",
                "total_invoice_amount", "total_paid_amount", "outstanding_amount"
            ];
            payment_fields.forEach(function(fieldname) {
                if (frm.fields_dict[fieldname]) {
                    frm.set_df_property(fieldname, "hidden", 1);
                }
            });
            
            // Hide price and discount columns in case_items table
            if (frm.fields_dict.case_items && frm.fields_dict.case_items.grid) {
                const grid = frm.fields_dict.case_items.grid;
                
                // Hide columns
                if (grid.docfields) {
                    grid.docfields.forEach(function(df) {
                        if (df.fieldname === "unit_price" || df.fieldname === "discount_pct") {
                            df.hidden = 1;
                            df.in_list_view = 0;
                        }
                    });
                }
                
                // Refresh grid to apply changes
                grid.refresh();
            }
        }
    }
});

frappe.ui.form.on("Dispatch Case Item", {
    form_render(frm, cdt, cdn) {
        // Hide price fields in grid row detail view
        const financial_roles = ["Ops - Accounting", "Ops - Finance", "Ops - Directors", "System Manager"];
        const user_roles = frappe.user_roles || [];
        const has_financial_access = financial_roles.some(role => user_roles.includes(role));
        
        if (!has_financial_access) {
            const row = locals[cdt][cdn];
            const grid_row = frm.fields_dict.case_items.grid.grid_rows_by_docname[row.name];
            
            if (grid_row && grid_row.docfields) {
                grid_row.docfields.forEach(function(df) {
                    if (df.fieldname === "unit_price" || df.fieldname === "discount_pct") {
                        df.hidden = 1;
                    }
                });
            }
        }
    }
});
'@

# Update Task client script to auto-fill prices from Item master when creating Dispatch Case
$TaskCreateDispatchCaseScript = @'
frappe.ui.form.on("Task", {
    refresh: function(frm) {
        if (frm.fields_dict.custom_product_lines) {
            frm.fields_dict.custom_product_lines.grid.get_field("item_name").get_query = function(doc, cdt, cdn) {
                let row = locals[cdt][cdn];
                return {};
            };
        }
    }
});

frappe.ui.form.on("Task", {
    refresh: function(frm) {
        if (frm.fields_dict.custom_product_lines) {
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
                                            fields: ["name", "item_name", "item_group"],
                                            limit_page_length: 100
                                        },
                                        callback: function(r) {
                                            if (r.message && r.message.length > 0) {
                                                let html = "<div style='max-height: 300px; overflow-y: auto;'><table class='table table-bordered'><thead><tr><th width='5%'></th><th>Item Name</th></tr></thead><tbody>";
                                                r.message.forEach(function(item) {
                                                    html += "<tr><td><input type='checkbox' class='item-checkbox' data-item='" + item.name + "'></td><td>" + item.item_name + " <small>(" + item.name + ")</small></td></tr>";
                                                });
                                                html += "</tbody></table></div>";
                                                d.fields_dict.items_html.$wrapper.html(html);
                                            } else {
                                                d.fields_dict.items_html.$wrapper.html("<p class='text-muted'>No items found in this category</p>");
                                            }
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
                            selected.push($(this).data("item"));
                        });
                        
                        if (selected.length === 0) {
                            frappe.msgprint(__("Please select at least one item"));
                            return;
                        }
                        
                        selected.forEach(function(item_name) {
                            let row = frm.add_child("custom_product_lines");
                            row.item_name = item_name;
                            row.qty = 1;
                            row.warehouse = "Main - Inmed";
                        });
                        
                        frm.refresh_field("custom_product_lines");
                        frappe.show_alert({message: __("Added {0} item(s)", [selected.length]), indicator: "green"});
                        d.hide();
                    }
                });
                d.show();
            }, __("Products"));
            
            // Add "Create Dispatch Case from Task" button with auto-fill prices
            if (frm.doc.name && frm.doc.custom_product_lines && frm.doc.custom_product_lines.length > 0) {
                frm.add_custom_button(__("Create Dispatch Case from Task"), function() {
                    frappe.confirm(
                        __("Create a new Dispatch Case with all items from this Task?"),
                        function() {
                            // Create new Dispatch Case
                            frappe.call({
                                method: "frappe.client.insert",
                                args: {
                                    doc: {
                                        doctype: "Dispatch Case",
                                        customer: frm.doc.customer || "",
                                        client_location_warehouse: "Main - Inmed",
                                    }
                                },
                                callback: function(r) {
                                    if (r.message) {
                                        let dispatch_case = r.message.name;
                                        
                                        // Get the Dispatch Case doc and add items with prices
                                        frappe.model.with_doc("Dispatch Case", dispatch_case, function() {
                                            let dc_doc = frappe.model.get_doc("Dispatch Case", dispatch_case);
                                            
                                            // Fetch prices for all items first
                                            let items_to_fetch = frm.doc.custom_product_lines.map(line => line.item_code || line.item_name);
                                            
                                            frappe.call({
                                                method: "frappe.client.get_list",
                                                args: {
                                                    doctype: "Item",
                                                    filters: [["name", "in", items_to_fetch]],
                                                    fields: ["name", "standard_rate"]
                                                },
                                                callback: function(price_r) {
                                                    let price_map = {};
                                                    if (price_r.message) {
                                                        price_r.message.forEach(function(item) {
                                                            price_map[item.name] = item.standard_rate || 0;
                                                        });
                                                    }
                                                    
                                                    // Copy product lines from Task to Dispatch Case with prices
                                                    frm.doc.custom_product_lines.forEach(function(line) {
                                                        let child = frappe.model.add_child(dc_doc, "Dispatch Case Item", "case_items");
                                                        let item_code = line.item_code || line.item_name;
                                                        child.item_code = item_code;
                                                        child.item_name = line.item_name;
                                                        child.dispatched_qty = line.qty || 1;
                                                        child.batch_no = line.batch_no || "";
                                                        child.unit_price = price_map[item_code] || 0;
                                                        child.discount_pct = 0;
                                                    });
                                                    
                                                    // Save the Dispatch Case with items
                                                    frappe.call({
                                                        method: "frappe.client.save",
                                                        args: {
                                                            doc: dc_doc
                                                        },
                                                        callback: function() {
                                                            frappe.show_alert({
                                                                message: __("Dispatch Case {0} created with {1} items and prices auto-filled", [dispatch_case, frm.doc.custom_product_lines.length]),
                                                                indicator: "green"
                                                            });
                                                            
                                                            // Open the new Dispatch Case
                                                            frappe.set_route("Form", "Dispatch Case", dispatch_case);
                                                        }
                                                    });
                                                }
                                            });
                                        });
                                    }
                                }
                            });
                        }
                    );
                }, __("Actions"));
            }
        }
    }
});
'@

$ClientScripts = @(
    [pscustomobject]@{ name="Dispatch Case-Price Visibility"; dt="Dispatch Case"; script=$DispatchCasePriceVisibilityScript }
)

$Report = [ordered]@{ mode=$Mode; client_scripts=@(); notes=@() }

foreach ($c in $ClientScripts) {
    $Existing = Get-ErpDoc -DocType "Client Script" -Name $c.name
    $Report.client_scripts += [pscustomobject]@{ name=$c.name; exists=($null -ne $Existing); action=if($Mode -eq "Deploy"){ "upsert" } else { "check_only" } }
    if ($Mode -eq "Deploy") {
        $Body = [ordered]@{ dt=$c.dt; view="Form"; enabled=1; script=$c.script }
        $Report.client_scripts[-1] = Upsert-ErpDoc -DocType "Client Script" -Name $c.name -Body $Body
    }
}

# Update existing Task client script with price auto-fill
if ($Mode -eq "Deploy") {
    $TaskScriptBody = [ordered]@{ dt="Task"; view="Form"; enabled=1; script=$TaskCreateDispatchCaseScript }
    $TaskScriptResult = Upsert-ErpDoc -DocType "Client Script" -Name "Task-Product Lines Display" -Body $TaskScriptBody
    $Report.notes += "Updated Task client script to auto-fill prices from Item standard_rate when creating Dispatch Case"
    $Report.client_scripts += $TaskScriptResult
}

$Report.notes += "Price and discount fields hidden from non-accounting users (visible only to Ops - Accounting, Ops - Finance, Ops - Directors, System Manager)"
$Report.notes += "Invoice and Payment section hidden from non-accounting users"
$Report.notes += "Prices auto-fill from Item standard selling rate when creating Dispatch Case from Task"

$Report | ConvertTo-Json -Depth 10
