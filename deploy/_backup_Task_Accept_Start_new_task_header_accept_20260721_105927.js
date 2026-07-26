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
        // Global: fix page title overflow ÃÂ¢ÃÂÃÂ title row 1, buttons row 2
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
            "Returns restocking", "Invoice preparation / create invoice", "Debt Collection", "Debt Closure Approval", "Account details",
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
                    btn.data("busy", true).prop("disabled", true).text("Saving...");
                    var timeoutId = setTimeout(function() {
                        btn.data("busy", false).prop("disabled", false).css("background-color", "#e74c3c").text("Timeout");
                        frappe.show_alert({message: "Complete Task timed out after 30 seconds. Please try again.", indicator: "red"}, 10);
                    }, 30000);
                    function resetButton() {
                        clearTimeout(timeoutId);
                        btn.data("busy", false).prop("disabled", false).css("background-color", "#e74c3c").text("Complete Task");
                    }
                    frm.save()
                        .then(function() {
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
        if ((!frm.is_new() || isOrderEntry) && operationalKinds.includes(frm.doc.task_kind) && ["Open", "Working"].includes(frm.doc.status) && frm.doc.custom_accepted_by !== frappe.session.user) {
            // Mobile: big inline Accept button at top of form
            if (window.innerWidth <= 768) {
                var mAccept = $("<button id=\"mobile-accept-btn\" style=\"width:100%;padding:16px;font-size:18px;font-weight:bold;background:#1976d2;color:#fff;border:none;border-radius:10px;margin:10px 0 20px 0;cursor:pointer;box-shadow:0 3px 8px rgba(0,0,0,0.2);\">Accept / Start Task</button>");
                mAccept.on("click", function() {
                    var doAcceptM = function() {
                        frappe.call({
                            method: "dispatch_task_accept",
                            args: { task_name: frm.doc.name },
                            freeze: true,
                            freeze_message: __("Accepting task..."),
                            callback: function() { frm.reload_doc(); }
                        });
                    };
                    if (frm.is_new() || frm.dirty()) {
                        frm.save().then(function() { doAcceptM(); });
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
                        args: { task_name: frm.doc.name },
                        freeze: true,
                        freeze_message: __("Accepting task..."),
                        callback: function() {
                            frm.reload_doc();
                        }
                    });
                };
                if (frm.is_new() || frm.dirty()) {
                    frm.save().then(function() {
                        doAccept();
                    });
                } else {
                    doAccept();
                }
            });
        }
    }
});

