// Name: Task-Accept Start
// DocType: Task
// Enabled: 1
// ---


function account_details_entry_ui_cleanup(frm) {
    if (frm.doc.task_kind !== "Account Details: Entry") return;

    var hideFields = [
        "custom_task_scan_barcode",
        "custom_task_scan_qty",
        "custom_task_choose_product",
        "custom_task_product_qty",
        "custom_task_add_batch_no",
        "custom_task_add_unit_price"
    ];

    hideFields.forEach(function(fieldname) {
        if (frm.fields_dict[fieldname]) {
            frm.toggle_display(fieldname, false);
            frm.set_df_property(fieldname, "hidden", 1);
        }
        $(frm.wrapper).find('[data-fieldname="' + fieldname + '"]').closest('.frappe-control').hide();
    });

    ["status", "priority"].forEach(function(fieldname) {
        if (frm.fields_dict[fieldname]) frm.toggle_display(fieldname, true);
    });

    if (frm.fields_dict.custom_account_photos) {
        frm.toggle_display("custom_account_photos", true);
    }

    setTimeout(function() {
        [
            "Barcode Scanning (Optional)",
            "Scan Product Barcode",
            "Scan Qty",
            "Choose Product",
            "Product Qty",
            "Batch / LOT",
            "Unit Price",
            "Warehouse Pickup Photo",
            "Warehouse Drop-off Photo"
        ].forEach(function(label) {
            $(frm.wrapper).find('.section-head').filter(function() { return $(this).text().trim() === label; }).closest('.form-section').hide();
            $(frm.wrapper).find('.control-label, label').filter(function() { return $(this).text().trim() === label; }).closest('.frappe-control').hide();
        });
    }, 300);

    $(frm.wrapper).find("#account-details-add-photos-btn").remove();
}
frappe.ui.form.on("Task", {
    custom_assigned_to(frm) {
        if (frm.doc.custom_assigned_to) {
            frm.set_value("custom_team_queue_role", "");
        }
    },
    custom_team_queue_role(frm) {
        if (frm.doc.custom_team_queue_role) {
            frm.set_value("custom_assigned_to", "");
        }
    },
    status(frm) {
        if (frm.doc.status === "Completed" && !frm.doc.completed_on) {
            frm.set_value("completed_on", frappe.datetime.get_today());
        }
    },
    after_save(frm) {
        $(frm.wrapper).find("#task-save-btn").hide();
    },
    onchange(frm) {
        if (frm.is_dirty()) {
            $(frm.wrapper).find("#task-save-btn").show();
        }
    },
    refresh(frm) {
        task_mobile_hide_desktop_custom_actions();
        task_mobile_update_action_state(frm);
        setTimeout(function() { task_mobile_hide_header_custom_buttons(frm); task_mobile_render_compact_actions(frm); }, 300);
        setTimeout(function() { task_mobile_hide_header_custom_buttons(frm); task_mobile_render_compact_actions(frm); }, 900);
        // Mobile back button (once, persists via setInterval across all pages)
        if (!window._mobileBackInterval) {
            (function() {
                function ensureBackBtn() {
                    var btn = document.getElementById('mobile-back-btn');
                    if (window.innerWidth > 768) { if (btn) btn.style.display = 'none'; return; }
                    var url = window.location.href.toLowerCase();
                    var isHome = url.endsWith('/app') || url.endsWith('/app/') || url.includes('/app/home') || url.includes('/app/modules') || url.includes('/app/desk');
                    if (isHome) { if (btn) btn.style.display = 'none'; return; }
                    if (!btn) {
                        btn = document.createElement('div');
                        btn.id = 'mobile-back-btn';
                        btn.textContent = '\u2190';
                        btn.style.cssText = 'position:fixed;bottom:20px;left:20px;width:56px;height:56px;border-radius:50%;background:#1976d2;color:#fff;font-size:30px;display:flex;align-items:center;justify-content:center;box-shadow:0 4px 12px rgba(0,0,0,0.3);z-index:99999;cursor:pointer;user-select:none;-webkit-tap-highlight-color:transparent;';
                        btn.addEventListener('click', function() { history.back(); });
                        document.body.appendChild(btn);
                    }
                    btn.style.display = 'flex';
                }
                window._mobileBackInterval = setInterval(ensureBackBtn, 1000);
                ensureBackBtn();
            })();
        }
        // Global: fix page title overflow
        (function() {
            var phc = $(frm.page.wrapper).find('.page-head-content');
            var ta = $(frm.page.wrapper).find('.title-area');
            var tt = $(frm.page.wrapper).find('.title-text');
            var pa = $(frm.page.wrapper).find('.page-actions');
            if (phc.length) phc.css({'flex-wrap': 'wrap', 'gap': '6px 0'});
            if (ta.length) ta.css({'flex': '1 1 100%', 'min-width': '0', 'overflow': 'hidden'});
            if (tt.length) tt.css({'overflow': 'hidden', 'text-overflow': 'ellipsis', 'white-space': 'nowrap', 'display': 'block'});
            if (pa.length) pa.css({'flex': '0 0 auto', 'gap': '6px', 'flex-wrap': 'wrap', 'justify-content': 'flex-end'});
        })();
        // Mobile: inject global CSS + menu cleanup (once, on any page)
        if (window.innerWidth <= 768 && !document.getElementById("mobile-global-css")) {
            var css = document.createElement("style");
            css.id = "mobile-global-css";
            css.textContent = [
                "@media(max-width:768px){",
                ".menu-btn-group .dropdown-menu{min-width:92vw!important;white-space:normal!important}",
                ".page-actions .btn-sm{padding:4px 8px!important;font-size:12px!important}",
                ".page-actions{gap:2px!important;flex-wrap:nowrap!important}",
                "}"
            ].join("");
            document.head.appendChild(css);
            // Hide "Menu" text label
            document.querySelectorAll(".menu-btn-group .dropdown-toggle").forEach(function(btn) {
                btn.childNodes.forEach(function(n) {
                    if (n.nodeType === 3 && n.textContent.trim() === "Menu") n.textContent = "";
                });
                btn.querySelectorAll("span").forEach(function(sp) {
                    if (sp.textContent.trim() === "Menu") sp.style.display = "none";
                });
            });
        }
        if (window.innerWidth <= 768 && !window._mobileMenuSetup) {
            window._mobileMenuSetup = true;
            $(document).on("shown.bs.dropdown", function(e) {
                var dd = $(e.target).closest(".menu-btn-group, .dropdown").find(".dropdown-menu");
                if (!dd.length) dd = $(".dropdown-menu:visible");
                if (!dd.length) return;
                var hide = ["Toggle Sidebar","Email","Reload","Delete","Duplicate","New Task","Jump to field","Show Links","Copy to Clipboard","Remind Me","Undo","Redo","Customize","Edit DocType"];
                dd.find("a, button").each(function() {
                    var el = $(this);
                    var t = $.trim(el.clone().children("span, kbd, .text-muted").remove().end().text());
                    if (!t) t = $.trim(el.text());
                    for (var i = 0; i < hide.length; i++) {
                        if (t.indexOf(hide[i]) === 0) { el.hide(); el.parent("li").hide(); break; }
                    }
                });
                dd.find(".dropdown-divider, hr").hide();
                dd.css({"max-height":"70vh","overflow-y":"auto"});
                dd.find("a:visible, button:visible").css({"padding":"12px 18px","font-size":"15px","line-height":"1.5","white-space":"normal","word-wrap":"break-word","border-bottom":"1px solid #eee","margin":"0"});
            });
        }
        // Mobile: add Refresh button to form top bar
        if (window.innerWidth <= 768) {
            var formPage = $(frm.page.wrapper);
            if (!formPage.find("#mobile-form-refresh").length) {
                var rBtn = $("<button id=\"mobile-form-refresh\" class=\"btn btn-default btn-sm\" style=\"margin-right:3px;font-size:14px;width:28px;height:28px;padding:0;display:inline-flex;align-items:center;justify-content:center;\">&#x21bb;</button>");
                rBtn.on("click", function() { frm.reload_doc(); });
                formPage.find(".page-actions").prepend(rBtn);
            }
        }
        
        // Unified assignment UI
        frm.toggle_display("custom_team_queue_role", false);
        frm.set_df_property("custom_assigned_to", "label", "Assign To");
        frm.set_df_property("custom_next_task_assign_to", "label", "Next Task: Assign To");
        
        // Show next-task assignment for dispatch workflow tasks
        const dispatchKinds = ["Order entry", "Pack / prepare items", "Delivery", "Return Call", "Pickup Returns", "Returns processing / verification", "Returns restocking", "Invoice preparation / create invoice", "Discount Approval"];
        if (dispatchKinds.includes(frm.doc.task_kind) || frm.doc.task_kind === "Account Details: Entry") {
            frm.set_df_property("custom_next_task_assign_to", "hidden", 0);
        } else {
            frm.set_df_property("custom_next_task_assign_to", "hidden", 1);
        }
        account_details_entry_ui_cleanup(frm);
        if (frm.doc.task_kind === "Account Details: Entry" && frm.fields_dict.custom_next_task_assign_to) { frm.set_df_property("custom_next_task_assign_to", "hidden", 0); frm.toggle_display("custom_next_task_assign_to", true); }
        account_details_entry_keep_next_assign_empty(frm);
        // Hide sidebar items: Assign, Tags, Share, Like
        try {
            $(frm.wrapper).find('.like-action').hide();
            $(frm.wrapper).find('.form-assignments').hide();
            $(frm.wrapper).find('.form-tags').hide();
            $(frm.wrapper).find('.form-shared').hide();
        } catch(e) {}
        // Hide internal fields for clean UI
        frm.toggle_display("custom_is_team_queue_task", false);
        frm.toggle_display("custom_team_queue_status", false);
        frm.toggle_display("custom_team_notified", false);
        frm.toggle_display("custom_accepted_by", false);
        if (frm.doc.custom_accepted_by) {
            frm.toggle_display("custom_team_queue_role", false);
        }
        frm.set_df_property("subject", "reqd", 0);
        if (frm.fields_dict.subject && frm.fields_dict.subject.df) {
            frm.fields_dict.subject.df.reqd = 0;
        }
        if (frm.doc.task_kind === "Order entry") {
            frm.toggle_display("subject", false);
            if (!frm.doc.subject) {
                frm.set_value("subject", frm.doc.name || "Order entry");
            }
        }
        // Hide Activity/Timesheet dashboard for all tasks
        frm.dashboard.hide();
        // Mobile: hide clutter fields for clean mobile UI
        if (window.innerWidth <= 768) {
            setTimeout(function() {
                var hideFields = ["custom_is_team_queue_task","custom_team_queue_status","custom_accepted_at","custom_team_notified","custom_task_add_batch_no","custom_task_add_unit_price"];
                hideFields.forEach(function(fn) {
                    $(frm.wrapper).find("[data-fieldname=\"" + fn + "\"]").closest(".frappe-control").hide();
                });
                $(frm.wrapper).find(".form-section .help-box").hide();
                // Hide Timeline section on mobile
                $(frm.wrapper).find(".form-footer .timeline-group, .form-footer .timeline-actions").hide();
                $(frm.wrapper).find(".section-head:contains('Timeline')").closest(".form-section").hide();
            }, 200);
        }
        // Default task_kind to Order entry on full form for new tasks
        if (frm.is_new() && frm.doc.task_kind === "Order accepting") {
            frm.set_value("task_kind", "Order entry");
        }
        var isOrderEntry = (frm.doc.task_kind === "Order entry");
        const operationalKinds = [
            "Order entry", "Pack / prepare items", "Dispatch picking / hand-off", "Delivery", "Return Call",
            "Pickup Returns", "Return drop-off at warehouse", "Returns processing / verification",
            "Returns restocking", "Invoice preparation / create invoice", "Debt Collection", "Debt Closure Approval", "Account Details: Entry", "Account Details: Processing",
            "Discount Approval", "Purchase Approval", "Write-off Approval"
        ];
        // Save + Complete buttons near status field
        var statusField = frm.fields_dict.status;
        if (statusField && statusField.$wrapper) {
            statusField.$wrapper.find("#task-save-btn").remove();
            statusField.$wrapper.find("#complete-task-btn").remove();
            if (!frm.is_new() && frm.doc.status !== "Completed" && frm.doc.status !== "Cancelled") {
                var saveBtn = $('<button id="task-save-btn" class="btn" style="background-color:#1976d2;color:#fff;font-weight:bold;font-size:13px;padding:7px 20px;border:none;border-radius:5px;cursor:pointer;margin-top:8px;display:block;">Save</button>');
                saveBtn.on("click", function() {
                    saveBtn.prop("disabled", true).text("Saving...");
                    frm.save().then(function() {
                        saveBtn.prop("disabled", false).text("Save");
                    }).catch(function() {
                        saveBtn.prop("disabled", false).text("Save");
                    });
                });
                statusField.$wrapper.append(saveBtn);
                // Show/hide save button based on dirty state
                if (frm.is_dirty()) { saveBtn.show(); } else { saveBtn.hide(); }
                var btn = $('<button id="complete-task-btn" class="btn" style="background-color:#e74c3c;color:#fff;font-weight:bold;font-size:13px;padding:7px 20px;border:none;border-radius:5px;cursor:pointer;margin-top:8px;display:block;">Complete Task</button>');
                btn.on("click", function() {
                    if (btn.data("busy")) return;
                    var originalStatus = frm.doc.status;
                    var originalCompletedOn = frm.doc.completed_on;
                    var hasUnsavedWork = frm.is_dirty();
                    btn.data("busy", true).prop("disabled", true).text(hasUnsavedWork ? "Saving..." : "Completing...");
                    var timeoutId = setTimeout(function() {
                        btn.data("busy", false).prop("disabled", false).css("background-color", "#e74c3c").text("Timeout");
                        frappe.show_alert({message: "Complete Task timed out after 30 seconds. Please try again.", indicator: "red"}, 10);
                    }, 30000);
                    function resetButton() {
                        clearTimeout(timeoutId);
                        btn.data("busy", false).prop("disabled", false).css("background-color", "#e74c3c").text("Complete Task");
                    }
                    var saveBeforeComplete = hasUnsavedWork ? frm.save() : Promise.resolve();
                    saveBeforeComplete
                        .then(function() {
                            if (frm.doc.status === "Completed") {
                                clearTimeout(timeoutId);
                                btn.css("background-color", "#27ae60").text("Completed ?");
                                return frm.reload_doc();
                            }
                            btn.text("Completing...");
                            frm.doc.status = "Completed";
                            if (!frm.doc.completed_on) {
                                frm.doc.completed_on = frappe.datetime.get_today();
                            }
                            frm.dirty();
                            return frm.save();
                        })
                        .then(function() {
                            clearTimeout(timeoutId);
                            btn.css("background-color", "#27ae60").text("Completed \u2713");
                            return frm.reload_doc();
                        })
                        .catch(function(err) {
                            frm.doc.status = originalStatus;
                            if (frm.doc.completed_on !== originalCompletedOn) {
                                frm.doc.completed_on = originalCompletedOn || "";
                            }
                            resetButton();
                            frappe.show_alert({message: "Failed: " + (err.message || err), indicator: "red"}, 10);
                        });
                });
                statusField.$wrapper.append(btn);
            } else if (frm.doc.status === "Completed") {
                statusField.$wrapper.append('<div id="complete-task-btn" style="background-color:#27ae60;color:#fff;font-weight:bold;font-size:13px;padding:7px 20px;border-radius:5px;margin-top:8px;display:inline-block;text-align:center;">Completed \u2713</div>');
            }
        }

        // Mobile: always clean up and re-render accept button
        $(frm.wrapper).find("#mobile-accept-btn").remove();
        if (window.innerWidth <= 768 && frm.doc.custom_accepted_by === frappe.session.user) {
            $(frm.wrapper).find(".form-layout").prepend('<div id="mobile-accept-btn" style="width:100%;padding:14px;font-size:17px;font-weight:bold;background:#999;color:#fff;border-radius:10px;margin:10px 0 20px 0;text-align:center;">Accepted</div>');
        }
        if (((!frm.is_new()) || frm.doc.task_kind === "Account Details: Entry") && operationalKinds.includes(frm.doc.task_kind) && ["Open", "Working"].includes(frm.doc.status) && frm.doc.custom_accepted_by !== frappe.session.user) {
            // Mobile: big inline Accept button at top of form
            if (window.innerWidth <= 768) {
                var mAccept = $("<button id=\"mobile-accept-btn\" style=\"width:100%;padding:16px;font-size:18px;font-weight:bold;background:#1976d2;color:#fff;border:none;border-radius:10px;margin:10px 0 20px 0;cursor:pointer;box-shadow:0 3px 8px rgba(0,0,0,0.2);\">Accept / Start Task</button>");
                mAccept.on("click", function() {
                    var doAcceptM = function() {
                        frappe.call({
                            method: "dispatch_task_accept",
                            args: { task_name: ((frm.doc && frm.doc.name && frm.doc.name.indexOf("new-") !== 0) ? frm.doc.name : "") },
                            freeze: true,
                            freeze_message: __("Accepting task..."),
                            callback: function() { frm.reload_doc(); }
                        });
                    };
                    if (frm.is_new() || frm.dirty()) {
                        frm.save().then(function() { if (frm.doc.name && frm.doc.name.indexOf("new-") !== 0) { doAcceptM(); } else { frappe.show_alert({message: __("Task saved. Please click Accept / Start Task again."), indicator: "orange"}, 8); frm.reload_doc(); } });
                    } else {
                        doAcceptM();
                    }
                });
                $(frm.wrapper).find(".form-layout").prepend(mAccept);
            }
            frm.add_custom_button(__("Accept / Start Task"), function() {
                var doAccept = function() {
                    frappe.call({
                        method: "dispatch_task_accept",
                        args: { task_name: ((frm.doc && frm.doc.name && frm.doc.name.indexOf("new-") !== 0) ? frm.doc.name : "") },
                        freeze: true,
                        freeze_message: __("Accepting task..."),
                        callback: function() {
                            frm.reload_doc();
                        }
                    });
                };
                if (frm.is_new() || frm.dirty()) {
                    frm.save().then(function() {
                        if (frm.doc.name && frm.doc.name.indexOf("new-") !== 0) { doAccept(); } else { frappe.show_alert({message: __("Task saved. Please click Accept / Start Task again."), indicator: "orange"}, 8); frm.reload_doc(); }
                    });
                } else {
                    doAccept();
                }
            });
        }
    }
});

function account_details_entry_keep_next_assign_empty(frm) {
    if (!frm || !frm.doc) return;
    if (String(frm.doc.task_kind || "").trim() !== "Account Details: Entry") return;
    var nextAssign = String(frm.doc.custom_next_task_assign_to || "").trim();
    var currentAssign = String(frm.doc.custom_assigned_to || "").trim();
    if (nextAssign && (!currentAssign || nextAssign === currentAssign)) {
        frm.set_value("custom_next_task_assign_to", "");
    }
}
function task_mobile_hide_desktop_custom_actions() {
    if (document.getElementById("task-mobile-hide-desktop-custom-actions")) return;
    var style = document.createElement("style");
    style.id = "task-mobile-hide-desktop-custom-actions";
    style.textContent = "@media (max-width: 768px) { body[data-route^='Form/Task'] .page-head .page-head-content { display: flex !important; align-items: center !important; flex-wrap: nowrap !important; min-width: 0 !important; width: 100% !important; } body[data-route^='Form/Task'] .page-head .title-area { flex: 1 1 auto !important; min-width: 0 !important; max-width: 100% !important; overflow: hidden !important; } body[data-route^='Form/Task'] .page-head .title-text, body[data-route^='Form/Task'] .page-head .title-text a, body[data-route^='Form/Task'] .page-head .title-text span, body[data-route^='Form/Task'] .page-head h3, body[data-route^='Form/Task'] .page-head .ellipsis { white-space: nowrap !important; word-break: normal !important; overflow-wrap: normal !important; overflow: hidden !important; text-overflow: ellipsis !important; line-height: 1.25 !important; max-width: 100% !important; } body[data-route^='Form/Task'] .page-head .page-actions, body[data-route^='Form/Task'] .page-head .standard-actions { flex: 0 0 auto !important; min-width: 0 !important; margin-left: 6px !important; overflow: visible !important; } body[data-route^='Form/Task'] .page-head .custom-actions, body[data-route^='Form/Task'] .page-head .actions-btn-group { display: none !important; } #task-mobile-compact-actions { display: flex !important; gap: 8px !important; overflow-x: auto !important; padding: 8px 8px 2px 8px !important; margin: -6px 0 8px 0 !important; scrollbar-width: none !important; } #task-mobile-compact-actions::-webkit-scrollbar { display: none !important; } #task-mobile-compact-actions .task-mobile-action-square { flex: 0 0 auto !important; width: 42px !important; height: 38px !important; min-width: 42px !important; padding: 0 !important; border-radius: 10px !important; border: 1px solid #d1d8dd !important; background: #fff !important; color: #1f272e !important; font-weight: 700 !important; font-size: 13px !important; display: inline-flex !important; align-items: center !important; justify-content: center !important; box-shadow: 0 1px 3px rgba(0,0,0,0.12) !important; } }";
    document.head.appendChild(style);
}

function task_mobile_update_action_state(frm) {
    if (!frm || !frm.doc) return;
    document.body.classList.toggle("task-mobile-accepted-by-me", frm.doc.custom_accepted_by === frappe.session.user);
}

function task_mobile_action_symbol(label) {
    label = String(label || "").trim();
    if (!label) return "?";
    if (label.indexOf("Products") >= 0 || label.indexOf("Dispatch") >= 0) return "PD";
    if (label.indexOf("Complete") >= 0) return "OK";
    if (label.indexOf("Add") >= 0 || label.indexOf("New") >= 0) return "+";
    if (label.indexOf("Action") >= 0) return "AC";
    return label.split(/\s+/).map(function(part) { return part.charAt(0); }).join("").slice(0, 2).toUpperCase();
}

function task_mobile_render_compact_actions(frm) {
    if (!frm || !frm.doc || window.innerWidth > 768) return;
    $(frm.wrapper).find("#task-mobile-compact-actions").remove();
    if (frm.doc.custom_accepted_by !== frappe.session.user) return;
    var sourceButtons = [];
    $(frm.page.wrapper).find(".page-head .custom-actions .btn:visible, .page-head .actions-btn-group .btn:visible").each(function() {
        var original = $(this);
        var label = $.trim(original.text()).replace(/\s+/g, " ");
        if (!label || label === "Accept / Start Task") return;
        sourceButtons.push({ label: label, original: original });
    });
    if (!sourceButtons.length) return;
    var bar = $('<div id="task-mobile-compact-actions" aria-label="Task actions"></div>');
    sourceButtons.forEach(function(item) {
        var btn = $('<button type="button" class="task-mobile-action-square"></button>');
        btn.text(task_mobile_action_symbol(item.label));
        btn.attr("title", item.label);
        btn.attr("aria-label", item.label);
        btn.on("click", function() { item.original.trigger("click"); });
        bar.append(btn);
    });
    var accepted = $(frm.wrapper).find("#mobile-accept-btn").first();
    if (accepted.length) accepted.after(bar);
    else $(frm.wrapper).find(".form-layout").prepend(bar);
}
function task_mobile_hide_header_custom_buttons(frm) {
    if (!frm || window.innerWidth > 768) return;
    $(frm.page.wrapper).find(".page-head .custom-actions .btn, .page-head .actions-btn-group .btn").each(function() {
        var btn = $(this);
        var text = $.trim(btn.text()).replace(/\s+/g, " ");
        if (text && text !== "Save") btn.hide();
    });
}