// Mobile back button - runs when Workspace loads (covers home page entry)
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

// Mobile global CSS (if not already injected by another script)
if (window.innerWidth <= 768 && !document.getElementById("mobile-global-css")) {
    var _mcss = document.createElement("style");
    _mcss.id = "mobile-global-css";
    _mcss.textContent = "@media(max-width:768px){.page-actions{gap:2px!important;flex-wrap:nowrap!important}.page-actions .btn{padding:4px 6px!important;font-size:11px!important}.page-head .container{padding-left:8px!important;padding-right:8px!important}}img{image-orientation:from-image!important}";
    document.head.appendChild(_mcss);
}

frappe.ui.form.on('Workspace', {
    refresh: function(frm) {
        // Only trigger if we are viewing the public 'Home' desk template dashboard
        if (frm.doc.name === 'Home') {
            // Wait slightly for Frappe to finish rendering the desktop card containers
            setTimeout(() => {
                inject_clean_grid_shortcut();
            }, 300);
        }
    }
});

function inject_clean_grid_shortcut() {
    // Avoid creating duplicate icons if it's already there
    if ($("#custom-task-grid-shortcut").length > 0) return;

    // Locate the native container wrapper where the 12 icons live
    let gridContainer = $(".desk-container .desk-section [data-widget-type='shortcut']").parent();
    
    if (!gridContainer.length) {
        gridContainer = $(".desk-section .grid-container, .desk-container .desk-section");
    }

    if (gridContainer.length) {
        let customIconHtml = `
            <div id="custom-task-grid-shortcut" class="widget-widget-box" style="cursor: pointer; min-width: 140px; margin: 15px; text-align: center;" onclick="frappe.set_route('List', 'Task')">
                <div class="widget-head" style="display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 10px;">
                    <div class="shortcut-icon-wrapper" style="width: 72px; height: 72px; background-color: #eff6ff; border-radius: 16px; display: flex; align-items: center; justify-content: center; box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.05), 0 2px 4px -1px rgba(0, 0, 0, 0.03); transition: transform 0.2s ease;">
                        <svg class="icon" style="width: 32px; height: 32px; stroke: #2563eb; fill: none; stroke-width: 2;"><use href="#icon-ticket"></use></svg>
                    </div>
                    <span class="widget-title-link" style="font-size: 13px; font-weight: 500; color: #1f2937; margin-top: 4px; display: block;">Task List</span>
                </div>
            </div>
        `;

        // Appends the new shortcut directly alongside your existing 12 desktop elements
        gridContainer.append(customIconHtml);
        
        // Quick interactive hover polish matching standard ERPNext style
        $("#custom-task-grid-shortcut").hover(
            function() { $(this).find(".shortcut-icon-wrapper").css("transform", "translateY(-3px)"); },
            function() { $(this).find(".shortcut-icon-wrapper").css("transform", "translateY(0)"); }
        );
    }
}