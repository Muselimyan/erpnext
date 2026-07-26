#Requires -Version 5.1
param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check",
    [ValidateSet("test", "main")]
    [string]$Target = "test"
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$BaseUrl = if ($Target -eq "test") { "https://test.erpnext.am" } else { "https://erpnext.am" }
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }

$ScriptName = "Dispatch Case-Products Button"
Write-Host "=== Fix Dispatch Case Search First Click ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

$existing = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $ScriptName)?fields=[`"name`",`"script`"]" -Headers $Headers -Method Get -TimeoutSec 30
$script = $existing.data.script

$hasFix = ($script -match 'selected_search_items') -and ($script -match 'last_search_rendered_query') -and ($script -match 'searchFirstClick')
Write-Host "Has quick-search first-click fix: $(if($hasFix){'Yes'}else{'No'})"

if ($Mode -eq "Check") {
    if ($hasFix) { Write-Host "Status: fixed" -ForegroundColor Green } else { Write-Host "Status: needs deploy" -ForegroundColor Yellow }
    return
}

if ($hasFix) {
    Write-Host "Already fixed" -ForegroundColor Green
    return
}

$backupPath = Join-Path $PSScriptRoot ("_backup_Dispatch_Case_Products_Button_search_first_click_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".js")
$existing.data.script | Set-Content -Path $backupPath -Encoding UTF8
Write-Host "Backup: $backupPath" -ForegroundColor Green

$script = $script.Replace('                let d2 = new frappe.ui.Dialog({', "                let selected_search_items = {};`r`n                let last_search_rendered_query = null;`r`n                let d2 = new frappe.ui.Dialog({")

$oldOnchange = @'
                            onchange: function() {
                                let query = (d2.get_value("search_term") || "").trim();
                                if (query.length < 2) {
                                    d2.fields_dict.search_results_html.$wrapper.html("<p class='text-muted'>Type at least 2 characters to search...</p>");
                                    return;
                                }
                                d2.fields_dict.search_results_html.$wrapper.html("<p class='text-muted'>Searching...</p>");
                                frappe.call({
                                    method: "frappe.client.get_list",
                                    args: {
                                        doctype: "Item",
                                        or_filters: [
                                            ["item_name", "like", "%" + query + "%"],
                                            ["name", "like", "%" + query + "%"]
                                        ],
                                        fields: ["name", "item_name", "item_group", "standard_rate"],
                                        limit_page_length: 50
                                    },
                                    callback: function(r) {
                                        let items = r.message || [];
                                        if (items.length > 0) {
                                            let html = "<div style='max-height: 400px; overflow-y: auto;'>";
                                            html += "<table class='table table-bordered table-hover'>";
                                            html += "<thead><tr><th width='5%'></th><th>Item Name</th><th>Code</th><th>Group</th><th>Price</th></tr></thead>";
                                            html += "<tbody>";
                                            items.forEach(function(item) {
                                                let price = item.standard_rate ? frappe.format(item.standard_rate, {fieldtype: "Currency"}) : "-";
                                                html += "<tr>";
                                                html += "<td><input type='checkbox' class='item-checkbox' style='width:22px;height:22px;min-width:22px;min-height:22px;aspect-ratio:1/1;cursor:pointer' data-item='" + item.name + "' data-item-name='" + (item.item_name || item.name) + "' data-price='" + (item.standard_rate || 0) + "'></td>";
                                                html += "<td>" + (item.item_name || item.name) + "</td>";
                                                html += "<td><small>" + item.name + "</small></td>";
                                                html += "<td><small>" + (item.item_group || "") + "</small></td>";
                                                html += "<td>" + price + "</td>";
                                                html += "</tr>";
                                            });
                                            html += "</tbody></table></div>";
                                            html += "<p class='text-muted' style='margin-top: 5px;'>Found " + items.length + " items</p>";
                                            d2.fields_dict.search_results_html.$wrapper.html(html);
                                        } else {
                                            d2.fields_dict.search_results_html.$wrapper.html("<p class='text-muted'>No items found for: <strong>" + frappe.utils.escape_html(query) + "</strong></p>");
                                        }
                                    }
                                });
                            }
'@

$newOnchange = @'
                            onchange: function() {
                                let query = (d2.get_value("search_term") || "").trim();
                                if (query === last_search_rendered_query) return;
                                last_search_rendered_query = query;
                                if (query.length < 2) {
                                    d2.fields_dict.search_results_html.$wrapper.html("<p class='text-muted'>Type at least 2 characters to search...</p>");
                                    return;
                                }
                                d2.fields_dict.search_results_html.$wrapper.html("<p class='text-muted'>Searching...</p>");
                                frappe.call({
                                    method: "frappe.client.get_list",
                                    args: {
                                        doctype: "Item",
                                        or_filters: [
                                            ["item_name", "like", "%" + query + "%"],
                                            ["name", "like", "%" + query + "%"]
                                        ],
                                        fields: ["name", "item_name", "item_group", "standard_rate"],
                                        limit_page_length: 50
                                    },
                                    callback: function(r) {
                                        let items = r.message || [];
                                        if (items.length > 0) {
                                            let html = "<div style='max-height: 400px; overflow-y: auto;'>";
                                            html += "<table class='table table-bordered table-hover'>";
                                            html += "<thead><tr><th width='5%'></th><th>Item Name</th><th>Code</th><th>Group</th><th>Price</th></tr></thead>";
                                            html += "<tbody>";
                                            items.forEach(function(item) {
                                                let price = item.standard_rate ? frappe.format(item.standard_rate, {fieldtype: "Currency"}) : "-";
                                                html += "<tr>";
                                                html += "<td><input type='checkbox' class='item-checkbox' style='width:22px;height:22px;min-width:22px;min-height:22px;aspect-ratio:1/1;cursor:pointer' " + (selected_search_items[item.name] ? "checked " : "") + "data-item='" + item.name + "' data-item-name='" + (item.item_name || item.name) + "' data-price='" + (item.standard_rate || 0) + "'></td>";
                                                html += "<td>" + (item.item_name || item.name) + "</td>";
                                                html += "<td><small>" + item.name + "</small></td>";
                                                html += "<td><small>" + (item.item_group || "") + "</small></td>";
                                                html += "<td>" + price + "</td>";
                                                html += "</tr>";
                                            });
                                            html += "</tbody></table></div>";
                                            html += "<p class='text-muted' style='margin-top: 5px;'>Found " + items.length + " items</p>";
                                            d2.fields_dict.search_results_html.$wrapper.html(html);
                                        } else {
                                            d2.fields_dict.search_results_html.$wrapper.html("<p class='text-muted'>No items found for: <strong>" + frappe.utils.escape_html(query) + "</strong></p>");
                                        }
                                    }
                                });
                            }
'@

if (-not $script.Contains($oldOnchange)) {
    throw "Could not find quick-search onchange block to patch"
}
$script = $script.Replace($oldOnchange, $newOnchange)

$oldShow = @'
                d2.show();
                setTimeout(function() {
                    d2.fields_dict.search_term.$input.focus();
                }, 300);
'@

$newShow = @'
                d2.show();
                d2.$wrapper.on("change.searchFirstClick", ".item-checkbox", function() {
                    let item_code = $(this).attr("data-item");
                    if (item_code) selected_search_items[item_code] = $(this).is(":checked");
                });
                setTimeout(function() {
                    d2.fields_dict.search_term.$input.focus();
                }, 300);
'@

if (-not $script.Contains($oldShow)) {
    throw "Could not find quick-search d2.show block to patch"
}
$script = $script.Replace($oldShow, $newShow)

$body = @{ script = $script } | ConvertTo-Json -Depth 10 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $ScriptName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
Write-Host "Quick Search & Add Item first-click fix deployed" -ForegroundColor Green
