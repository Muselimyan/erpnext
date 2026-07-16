// Global mobile CSS + tooltip fix (runs once, persists across all pages)
if (window.innerWidth <= 768 && !document.getElementById("mobile-global-css")) {
    var _mcss = document.createElement("style");
    _mcss.id = "mobile-global-css";
    _mcss.textContent = "@media(max-width:768px){.page-actions{gap:2px!important;flex-wrap:nowrap!important}.page-actions .btn{padding:4px 6px!important;font-size:11px!important}.page-head .container{padding-left:8px!important;padding-right:8px!important}}img{image-orientation:from-image!important}";
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

// Mobile back button: setup globally (runs once, works on ALL pages)
(function() {
    if (window._mobileBackInterval) return;
    function ensureBackBtn() {
        var btn = document.getElementById('mobile-back-btn');
        if (window.innerWidth > 768) { if (btn) btn.style.display = 'none'; return; }
        var url = window.location.href.toLowerCase();
        var isHome = url.endsWith('/app') || url.endsWith('/app/') || url.includes('/app/home') || url.includes('/app/modules');
        if (isHome) { if (btn) btn.style.display = 'none'; return; }
        if (!btn) {
            btn = document.createElement('div');
            btn.id = 'mobile-back-btn';
            btn.textContent = '\u2190';
            btn.style.cssText = 'position:fixed;bottom:20px;left:20px;width:56px;height:56px;border-radius:50%;background:#1976d2;color:#fff;font-size:30px;display:flex;align-items:center;justify-content:center;box-shadow:0 4px 12px rgba(0,0,0,0.3);z-index:99999;cursor:pointer;user-select:none;-webkit-tap-highlight-color:transparent;';
            btn.addEventListener('click', function() { history.back(); });
            btn.addEventListener('touchstart', function() { this.style.transform = 'scale(0.9)'; });
            btn.addEventListener('touchend', function() { this.style.transform = 'scale(1)'; });
            document.body.appendChild(btn);
        }
        btn.style.display = 'flex';
    }
    window._mobileBackInterval = setInterval(ensureBackBtn, 300);
    ensureBackBtn();
})();

frappe.listview_settings['Task'] = frappe.listview_settings['Task'] || {};
var _origOnload = frappe.listview_settings['Task'].onload;
frappe.listview_settings['Task'].onload = function(listview) {
    if (_origOnload) _origOnload(listview);
    // Mobile: add Refresh button to list top bar
    if (window.innerWidth <= 768) {
        var listPage = $(listview.page.wrapper);
        if (!listPage.find("#mobile-list-refresh").length) {
            var rBtn = $("<button id=\"mobile-list-refresh\" class=\"btn btn-default btn-sm\" style=\"margin-right:3px;font-size:14px;width:28px;height:28px;padding:0;display:inline-flex;align-items:center;justify-content:center;\">&#x21bb;</button>");
            rBtn.on("click", function() { listview.refresh(); });
            listPage.find(".page-actions").prepend(rBtn);
        }
    }

    // === Task List Toggle Filters ===
    var TOGGLE_STATE = { my_tasks: 1, open_tasks: 1, completed: 0 };
    window._taskToggleState = TOGGLE_STATE;

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
                applyToggleFilter();
            });
            lbl.append(cb).append($('<span></span>').text(t.label));
            bar.append(lbl);
        });

        // Insert before the list results area
        var $listArea = $wrapper.find(".frappe-list");
        if ($listArea.length) {
            $listArea.before(bar);
        } else {
            $wrapper.find(".page-body").prepend(bar);
        }
    }

    function applyToggleFilter() {
        console.log("[TaskToggle] applyToggleFilter called", TOGGLE_STATE);
        frappe.call({
            method: "task_list_filtered",
            args: {
                my_tasks: TOGGLE_STATE.my_tasks,
                open_tasks: TOGGLE_STATE.open_tasks,
                completed: TOGGLE_STATE.completed
            },
            callback: function(r) {
                var names = (r && r.message) || [];
                console.log("[TaskToggle] API returned " + names.length + " tasks");
                if (names.length === 0) {
                    names = ["__NO_MATCH__"];
                }
                window._taskToggleNames = names;
                // Use cur_list to set filters
                var lv = cur_list || listview;
                // Remove existing name filter if any
                var filters = lv.filter_area.get();
                var newFilters = [];
                for (var i = 0; i < filters.length; i++) {
                    if (filters[i][1] !== "name") {
                        newFilters.push(filters[i]);
                    }
                }
                // Add our name filter
                newFilters.push(["Task", "name", "in", names]);
                lv.filter_area.clear().then(function() {
                    newFilters.forEach(function(f) {
                        lv.filter_area.add(f[0], f[1], f[2], f[3]);
                    });
                    lv.refresh();
                });
            },
            error: function(err) {
                console.error("[TaskToggle] API error:", err);
            }
        });
    }

    renderToggleBar();
    setTimeout(function() { applyToggleFilter(); }, 500);
};