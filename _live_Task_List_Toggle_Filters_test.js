frappe.listview_settings['Task'] = frappe.listview_settings['Task'] || {};
window._taskToggleDedicated = true;
var _taskToggleOrigOnload = frappe.listview_settings['Task'].onload;
frappe.listview_settings['Task'].onload = function(listview) {
    if (_taskToggleOrigOnload) _taskToggleOrigOnload(listview);
    var TOGGLE_STATE = window._taskToggleState || { my_tasks: 1, open_tasks: 1, completed: 0 };
    window._taskToggleState = TOGGLE_STATE;

    function renderToggleBar() {
        var $wrapper = $(listview.page.wrapper);
        $wrapper.find('#task-toggle-bar').remove();
        var bar = $('<div id="task-toggle-bar" data-task-toggle-stable="1" style="display:flex;gap:8px;padding:8px 12px;background:#f7f7f7;border-bottom:1px solid #d1d8dd;position:sticky;top:0;z-index:100;flex-wrap:wrap;align-items:center;"></div>');
        [
            { key: 'my_tasks', label: 'My Tasks' },
            { key: 'open_tasks', label: 'Open Tasks' },
            { key: 'completed', label: 'Completed' }
        ].forEach(function(t) {
            var lbl = $('<label style="display:flex;align-items:center;gap:5px;cursor:pointer;font-size:13px;font-weight:500;margin:0;padding:6px 10px;border-radius:6px;background:#fff;border:1px solid #d1d8dd;user-select:none;"></label>');
            var cb = $('<input type="checkbox" style="width:16px;height:16px;cursor:pointer;accent-color:#1976d2;">');
            cb.prop('checked', !!TOGGLE_STATE[t.key]);
            cb.on('change', function() {
                TOGGLE_STATE[t.key] = this.checked ? 1 : 0;
                applyToggleFilter();
            });
            lbl.append(cb).append($('<span></span>').text(t.label));
            bar.append(lbl);
        });
        var $listArea = $wrapper.find('.frappe-list').first();
        if ($listArea.length) $listArea.before(bar);
        else $wrapper.find('.page-body').first().prepend(bar);
    }

    function cleanTaskListRoute() {
        var cleanPath = '/desk/task/view/list';
        if (window.location.pathname === cleanPath && window.location.search) {
            window.history.replaceState(window.history.state || {}, document.title, cleanPath);
        }
    }

    function applyToggleFilter() {
        cleanTaskListRoute();
        var lv = cur_list || listview;
        
        lv.filter_area.clear().then(function() {
            var filtersToAdd = [];

            // 1. Filter assigned tasks to current user if "My Tasks" is checked
            if (TOGGLE_STATE.my_tasks) {
                filtersToAdd.push(['Task', '_assign', 'like', '%' + frappe.session.user + '%']);
            }

            // 2. Filter status based on "Open Tasks" / "Completed"
            if (TOGGLE_STATE.open_tasks && !TOGGLE_STATE.completed) {
                filtersToAdd.push(['Task', 'status', '!=', 'Completed']);
            } else if (!TOGGLE_STATE.open_tasks && TOGGLE_STATE.completed) {
                filtersToAdd.push(['Task', 'status', '=', 'Completed']);
            } else if (!TOGGLE_STATE.open_tasks && !TOGGLE_STATE.completed) {
                // If neither is checked, hide all
                filtersToAdd.push(['Task', 'status', '=', '__none__']);
            }

            // Apply filters cleanly without large name arrays
            if (filtersToAdd.length > 0) {
                lv.filter_area.add(filtersToAdd);
            } else {
                lv.refresh();
            }

            setTimeout(cleanTaskListRoute, 50);
            setTimeout(cleanTaskListRoute, 300);
            setTimeout(cleanTaskListRoute, 1000);
        });
    }

    function ensureToggleBar() {
        if (frappe.get_route && frappe.get_route()[0] !== 'List') return;
        if (frappe.get_route && frappe.get_route()[1] !== 'Task') return;
        var $wrapper = $(listview.page.wrapper);
        if (!$wrapper.find('#task-toggle-bar').length) {
            renderToggleBar();
        }
    }

    if (window._taskToggleStableInterval) {
        clearInterval(window._taskToggleStableInterval);
    }
    window._taskToggleStableInterval = setInterval(ensureToggleBar, 1000);
    if (window._taskToggleStableObserver) {
        window._taskToggleStableObserver.disconnect();
    }
    window._taskToggleStableObserver = new MutationObserver(function() {
        clearTimeout(window._taskToggleStableTimer);
        window._taskToggleStableTimer = setTimeout(ensureToggleBar, 100);
    });
    window._taskToggleStableObserver.observe(listview.page.wrapper, { childList: true, subtree: true });
    var old_refresh = listview.refresh;
    if (!listview._taskToggleRefreshPatched) {
        listview.refresh = function() {
            var out = old_refresh.apply(listview, arguments);
            setTimeout(ensureToggleBar, 200);
            setTimeout(ensureToggleBar, 800);
            return out;
        };
        listview._taskToggleRefreshPatched = true;
    }
    frappe.router.on('change', function() { setTimeout(ensureToggleBar, 300); });

    setTimeout(function() {
        cleanTaskListRoute();
        renderToggleBar();
        applyToggleFilter();
        setTimeout(ensureToggleBar, 1000);
    }, 300);
};
