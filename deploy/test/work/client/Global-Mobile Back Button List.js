// Name: Global-Mobile Back Button List
// DocType: Task
// Enabled: 1
// ---

// Global mobile CSS + tooltip fix (runs once, persists across all pages)
if (window.innerWidth <= 768 && !document.getElementById("mobile-global-css")) {
    var _mcss = document.createElement("style");
    _mcss.id = "mobile-global-css";
    _mcss.textContent = "@media(max-width:768px){.page-actions{gap:2px!important;flex-wrap:nowrap!important}.page-actions .btn{padding:4px 6px!important;font-size:11px!important}.page-head .container{padding-left:8px!important;padding-right:8px!important}}img{image-orientation:from-image!important}body[data-route^=\"Form/Task\"] #mobile-global-subheader{display:none!important}body[data-route^=\"Form/Task\"] #mobile-back-btn{display:none!important}";
    document.head.appendChild(_mcss);
    // Remove "Menu" tooltip from ... button
    function _removeMenuTooltip() {
        document.querySelectorAll(".menu-more-button").forEach(function(b) {
            b.removeAttribute("title");
            b.removeAttribute("data-original-title");
            b.removeAttribute("data-bs-original-title");
        });
    }
    _removeMenuTooltip();
    setTimeout(_removeMenuTooltip, 500);
    frappe.router.on("change", function() { setTimeout(_removeMenuTooltip, 300); });
}

// Global mobile sub-header: Back + Refresh on every mobile page (except Task forms
// which have their own richer sub-header from Task-Action Buttons.js).
// Replaces the old floating #mobile-back-btn circle.
(function() {
    if (window._globalMobileSubheader) return;
    window._globalMobileSubheader = true;

    // Remove any leftover floating circle from previous code
    var oldBtn = document.getElementById('mobile-back-btn');
    if (oldBtn) oldBtn.remove();
    if (window._mobileBackInterval && typeof window._mobileBackInterval !== 'string') {
        clearInterval(window._mobileBackInterval);
    }
    window._mobileBackInterval = 'replaced-by-subheader';

    function renderGlobalSubheader() {
        if (window.innerWidth > 768) {
            var el = document.getElementById('mobile-global-subheader');
            if (el) el.style.display = 'none';
            return;
        }
        var route = frappe.get_route() || [];
        // Skip home/workspace pages
        if (!route.length || route[0] === 'Workspaces' || route[0] === '') return;
        // Task forms have their own sub-header (Task-Action Buttons.js)
        if (route[0] === 'Form' && route[1] === 'Task') return;

        var pageHead = $('.page-head:visible').first();
        if (!pageHead.length) return;
        // Already injected after this page-head
        if (pageHead.next('#mobile-global-subheader').length) return;
        // Remove stale sub-header from a previous page
        $('#mobile-global-subheader').remove();

        var bar = $('<div id="mobile-global-subheader" style="display:flex;align-items:center;padding:6px 12px;background:#f7f7f7;border-bottom:1px solid #d1d8dd;gap:6px;"></div>');
        var backBtn = $('<button class="btn btn-default btn-sm" style="font-size:16px;padding:4px 10px;">&#x2190;</button>');
        backBtn.on('click', function() {
            if (window.history.length > 1) history.back();
            else frappe.set_route('/app');
        });
        var refreshBtn = $('<button class="btn btn-default btn-sm" style="font-size:14px;padding:4px 10px;">&#x21bb;</button>');
        refreshBtn.on('click', function() {
            if (window.cur_frm) cur_frm.reload_doc();
            else if (window.cur_list) cur_list.refresh();
            else location.reload();
        });
        bar.append(backBtn).append(refreshBtn);
        pageHead.after(bar);
    }

    frappe.router.on('change', function() {
        setTimeout(renderGlobalSubheader, 300);
    });
    setTimeout(renderGlobalSubheader, 300);
})();

// === Task List: Toggle Filters + Visibility ===
// Injects role-based visibility filters and toggle state into Frappe's
// standard reportview.get pipeline via get_args() override. No custom
// data source — standard pagination, sorting, and rendering all work.

frappe.listview_settings['Task'] = frappe.listview_settings['Task'] || {};
var _origOnload = frappe.listview_settings['Task'].onload;
frappe.listview_settings['Task'].onload = function(listview) {
    if (_origOnload) _origOnload(listview);

    // Refresh button now provided by global mobile sub-header

    // --- Toggle state with localStorage persistence ---
    var STORAGE_KEY = "inmed_task_list_toggles";
    var TOGGLE_STATE;
    try {
        var saved = localStorage.getItem(STORAGE_KEY);
        TOGGLE_STATE = saved ? JSON.parse(saved) : null;
    } catch(e) { TOGGLE_STATE = null; }
    if (!TOGGLE_STATE || typeof TOGGLE_STATE.my_tasks === "undefined") {
        TOGGLE_STATE = { my_tasks: 1, open_tasks: 1, completed: 0 };
    }
    window._taskToggleState = TOGGLE_STATE;

    function saveToggleState() {
        try { localStorage.setItem(STORAGE_KEY, JSON.stringify(TOGGLE_STATE)); }
        catch(e) { /* localStorage unavailable — state lost on nav, acceptable */ }
    }
    saveToggleState();

    // --- Fetch visibility metadata (once per page load, cached in window) ---
    // This tells us: allowed task kinds, team placeholders, admin status.
    // The data query itself is done by Frappe's standard reportview.get.
    if (!window._taskVisibility) {
        frappe.call({
            method: "task_list_filtered",
            async: true,
            callback: function(r) {
                if (r && r.message) {
                    window._taskVisibility = r.message;
                    console.log("[TaskToggle] visibility loaded", {
                        kinds: r.message.allowed_kinds ? r.message.allowed_kinds.length : 0,
                        teams: r.message.team_placeholders ? r.message.team_placeholders.length : 0,
                        admin: r.message.is_admin
                    });
                    // Re-refresh now that visibility data is available
                    listview.start = 0;
                    listview.refresh();
                }
            },
            error: function() {
                console.error("[TaskToggle] visibility API error — filters will not apply");
                // Leave window._taskVisibility unset; get_args will skip injection
            }
        });
    }

    // --- Override get_args to inject toggle + visibility filters ---
    var origGetArgs = listview.get_args.bind(listview);
    listview.get_args = function() {
        var args = origGetArgs();
        var vis = window._taskVisibility;
        if (!vis) return args;  // metadata not loaded yet — use standard unfiltered query

        // Ensure filters is an array we can append to
        if (!args.filters) args.filters = [];
        // Handle string-encoded filters from Frappe internals
        if (typeof args.filters === "string") {
            try { args.filters = JSON.parse(args.filters); } catch(e) { args.filters = []; }
        }

        // Role-based visibility: restrict to allowed task kinds (skip for admin)
        if (!vis.is_admin && vis.allowed_kinds && vis.allowed_kinds.length > 0) {
            args.filters.push(["Task", "task_kind", "in", vis.allowed_kinds]);
        }

        // Status filter based on toggle state
        var ts = TOGGLE_STATE;
        var noneSelected = !ts.my_tasks && !ts.open_tasks && !ts.completed;
        if (!noneSelected) {
            if (ts.open_tasks && ts.completed) {
                args.filters.push(["Task", "status", "!=", "Cancelled"]);
            } else if (ts.completed && !ts.open_tasks) {
                args.filters.push(["Task", "status", "=", "Completed"]);
            } else {
                // Default: exclude completed and cancelled
                args.filters.push(["Task", "status", "not in", ["Completed", "Cancelled"]]);
            }
        }

        // Assignment filter based on toggle state (using or_filters)
        if (!noneSelected) {
            var orFilters = [];
            var safeUser = (vis.user || "").replace(/%/g, "");

            if (ts.my_tasks) {
                orFilters.push(["Task", "_assign", "like", "%" + safeUser + "%"]);
            }

            if (ts.open_tasks || ts.completed) {
                // Team-available: unassigned + assigned to team placeholders
                orFilters.push(["Task", "_assign", "is", "not set"]);
                orFilters.push(["Task", "_assign", "=", "[]"]);
                orFilters.push(["Task", "_assign", "=", ""]);
                // Include user's own tasks in team view too
                if (!ts.my_tasks) {
                    orFilters.push(["Task", "_assign", "like", "%" + safeUser + "%"]);
                }
                // Team placeholder assignments
                var teams = vis.team_placeholders || [];
                for (var i = 0; i < teams.length; i++) {
                    var safeTp = teams[i].replace(/%/g, "");
                    orFilters.push(["Task", "_assign", "like", "%" + safeTp + "%"]);
                }
            }

            if (orFilters.length > 0) {
                args.or_filters = JSON.stringify(orFilters);
            }
        }

        return args;
    };

    // --- Hide misleading count badge ---
    // The standard count call (frappe.client.get_count) doesn't include our
    // visibility filters, so it shows total Tasks — wrong and confusing.
    if (!document.getElementById("task-list-hide-count-css")) {
        var countCSS = document.createElement("style");
        countCSS.id = "task-list-hide-count-css";
        countCSS.textContent = ".list-count { display: none !important; }";
        document.head.appendChild(countCSS);
    }

    // --- Render toggle bar ---
    function renderToggleBar() {
        var $wrapper = $(listview.page.wrapper);
        $wrapper.find("#task-toggle-bar").remove();

        var bar = $('<div id="task-toggle-bar" style="display:flex;gap:10px;padding:8px 15px;background:#f7f7f7;border-bottom:1px solid #d1d8dd;position:sticky;top:0;z-index:100;flex-wrap:wrap;align-items:center;"></div>');

        var toggles = [
            { key: "my_tasks", label: "My Tasks" },
            { key: "open_tasks", label: "Open Tasks" },
            { key: "completed", label: "Completed" }
        ];

        toggles.forEach(function(t) {
            var checked = TOGGLE_STATE[t.key] ? "checked" : "";
            var lbl = $('<label style="display:flex;align-items:center;gap:5px;cursor:pointer;font-size:13px;font-weight:500;margin:0;padding:5px 10px;border-radius:6px;background:#fff;border:1px solid #d1d8dd;user-select:none;"></label>');
            var cb = $('<input type="checkbox" ' + checked + ' style="width:16px;height:16px;cursor:pointer;accent-color:#1976d2;">');
            cb.on("change", function() {
                TOGGLE_STATE[t.key] = this.checked ? 1 : 0;
                saveToggleState();
                listview.start = 0;
                listview.refresh();
            });
            lbl.append(cb).append($('<span></span>').text(t.label));
            bar.append(lbl);
        });

        var $listArea = $wrapper.find(".frappe-list");
        if ($listArea.length) {
            $listArea.before(bar);
        } else {
            $wrapper.find(".page-body").prepend(bar);
        }
    }

    renderToggleBar();
    // No delayed applyToggleFilter or filter_area.clear needed —
    // Frappe's own refresh pipeline calls our get_args() automatically.
};