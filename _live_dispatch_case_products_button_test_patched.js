frappe.ui.form.on("Dispatch Case", {
    refresh: function(frm) {
        // Add "Products" button to select items by category
        if (!frm.is_new()) {
            frm.add_custom_button(__("Add Items by Category"), function() {
                let last_loaded_group = null;
                let all_items = [];
                let selected_items = {};
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
                                    d.set_value("search_items", "");
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
                                            all_items = r.message || [];
                                            dc_products_render_items(d, all_items, "", selected_items);
                                        },
                                        error: function(r) {
                                            d.fields_dict.items_html.$wrapper.html("<p class='text-danger'>Error loading items</p>");
                                        }
                                    });
                                }
                            }
                        },
                        {
                            fieldname: "search_items",
                            label: __("Search Items"),
                            fieldtype: "Data",
                            placeholder: "Type to search by name or code...",
                            onchange: function() {
                                let query = (d.get_value("search_items") || "").toLowerCase().trim();
                                if (window._dcProductsSearchTimeout) { clearTimeout(window._dcProductsSearchTimeout); }
                                window._dcProductsSearchTimeout = setTimeout(function() {
                                    dc_products_render_items(d, all_items, query, selected_items);
                                }, 200);
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
                                item_code: $(this).attr("data-item"),
                                item_name: $(this).data("item-name"),
                                price: $(this).data("price")
                            });
                        });
                        
                        if (selected.length === 0) {
                            frappe.msgprint(__("Please select at least one item"));
                            return;
                        }
                        
                        selected.forEach(function(item) {
                            let row = frm.add_child("case_items");
                            row.item_code = String(item.item_code || "");
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
                d.$wrapper.on("change", ".item-checkbox", function() {
                    let item_code = $(this).attr("data-item");
                    if (item_code) {
                        selected_items[item_code] = $(this).is(":checked");
                    }
                });
            }, __("Actions"));

            // Add "Search & Add Item" button for quick item search
            frm.add_custom_button(__("Search & Add Item"), function() {
                let d2 = new frappe.ui.Dialog({
                    title: __("Search & Add Item"),
                    size: "large",
                    fields: [
                        {
                            fieldname: "search_term",
                            label: __("Search by Name or Code"),
                            fieldtype: "Data",
                            placeholder: "Start typing item name or code...",
                            reqd: 1,
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
                        },
                        {
                            fieldname: "search_results_html",
                            fieldtype: "HTML",
                            options: "<p class='text-muted'>Type to search items by name or code...</p>"
                        }
                    ],
                    primary_action_label: __("Add Selected Items"),
                    primary_action: function(values) {
                        let selected = [];
                        d2.$wrapper.find(".item-checkbox:checked").each(function() {
                            selected.push({
                                item_code: $(this).attr("data-item"),
                                item_name: $(this).data("item-name"),
                                price: $(this).data("price")
                            });
                        });
                        if (selected.length === 0) {
                            frappe.msgprint(__("Please select at least one item"));
                            return;
                        }
                        selected.forEach(function(item) {
                            let row = frm.add_child("case_items");
                            row.item_code = String(item.item_code || "");
                            row.item_name = item.item_name;
                            row.dispatched_qty = 1;
                            row.unit_price = item.price || 0;
                        });
                        frm.refresh_field("case_items");
                        frappe.show_alert({
                            message: __("Added {0} item(s)", [selected.length]),
                            indicator: "green"
                        });
                        d2.hide();
                    }
                });
                d2.show();
                setTimeout(function() {
                    d2.fields_dict.search_term.$input.focus();
                }, 300);
            }, __("Actions"));
        }
    }
});

function dc_products_render_items(dialog, items, query, selected_items) {
    selected_items = selected_items || {};
    let filtered = items;
    if (query) {
        filtered = items.filter(function(item) {
            return (item.item_name || "").toLowerCase().indexOf(query) !== -1 ||
                   (item.name || "").toLowerCase().indexOf(query) !== -1;
        });
    }
    if (filtered.length > 0) {
        let html = "<div style='max-height: 400px; overflow-y: auto;'>";
        html += "<table class='table table-bordered table-hover'>";
        html += "<thead><tr><th width='5%'></th><th>Item Name</th><th>Item Code</th><th>Price</th></tr></thead>";
        html += "<tbody>";
        filtered.forEach(function(item) {
            let price = item.standard_rate ? frappe.format(item.standard_rate, {fieldtype: "Currency"}) : "-";
            html += "<tr>";
            html += "<td><input type='checkbox' class='item-checkbox' style='width:22px;height:22px;min-width:22px;min-height:22px;aspect-ratio:1/1;cursor:pointer' " + (selected_items[item.name] ? "checked " : "") + "data-item='" + item.name + "' data-item-name='" + (item.item_name || item.name) + "' data-price='" + (item.standard_rate || 0) + "'></td>";
            html += "<td>" + (item.item_name || item.name) + "</td>";
            html += "<td><small>" + item.name + "</small></td>";
            html += "<td>" + price + "</td>";
            html += "</tr>";
        });
        html += "</tbody></table></div>";
        html += "<p class='text-muted' style='margin-top: 5px;'>Showing " + filtered.length + " of " + items.length + " items</p>";
        dialog.fields_dict.items_html.$wrapper.html(html);
    } else if (items.length > 0) {
        dialog.fields_dict.items_html.$wrapper.html("<p class='text-muted'>No items match search: <strong>" + frappe.utils.escape_html(query) + "</strong></p>");
    } else {
        dialog.fields_dict.items_html.$wrapper.html("<p class='text-muted'>Select an Item Group to load items</p>");
    }
}
