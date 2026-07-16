// Mobile layout adaptations & Refresh engine - Task List Specific
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

// Global Mobile Back Button Session Tracker
(function() {
    if (window.innerWidth > 768) return;

    function ensureBackBtn() {
        var url = window.location.href.toLowerCase();
        
        // Hide button only on main app workspace dashboards
        var isHome = url.endsWith('/app') || 
                     url.endsWith('/app/') || 
                     url.includes('/app/home') || 
                     url.includes('/app/modules') || 
                     url.includes('/app/desk');

        var btn = document.getElementById('mobile-back-btn');

        if (isHome) {
            if (btn) btn.style.display = 'none';
            return;
        }

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

    // Attach to global window context
    if (window._mobileBackInterval) {
        clearInterval(window._mobileBackInterval);
    }
    window._mobileBackInterval = setInterval(ensureBackBtn, 300);

    ensureBackBtn();
})();

// Add Refresh button to the top of the Task List View
frappe.listview_settings['Task'] = frappe.listview_settings['Task'] || {};
var _origOnload = frappe.listview_settings['Task'].onload;
frappe.listview_settings['Task'].onload = function(listview) {
    if (_origOnload) _origOnload(listview);
    if (window.innerWidth <= 768) {
        var listPage = $(listview.page.wrapper);
        if (!listPage.find("#mobile-list-refresh").length) {
            var rBtn = $("<button id=\"mobile-list-refresh\" class=\"btn btn-default btn-sm\" style=\"margin-right:3px;font-size:14px;width:28px;height:28px;padding:0;display:inline-flex;align-items:center;justify-content:center;\">&#x21bb;</button>");
            rBtn.on("click", function() { listview.refresh(); });
            listPage.find(".page-actions").prepend(rBtn);
        }
    }
};
