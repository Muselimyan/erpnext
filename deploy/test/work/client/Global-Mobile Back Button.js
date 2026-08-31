// Name: Global-Mobile Back Button
// DocType: Task
// Enabled: 1
// ---

frappe.ui.form.on('Task', {
    refresh: function(frm) {
        if (window._mobileBackInterval && typeof window._mobileBackInterval !== 'string') {
            clearInterval(window._mobileBackInterval);
        }
        window._mobileBackInterval = 'global-mobile-back-button-stable';

        function buildMobileBackButton() {
            var btn = document.getElementById('mobile-back-btn');
            var is_mobile = window.innerWidth <= 768;
            var path = (window.location.pathname || '').toLowerCase().replace(/\/$/, '');
            var hash = (window.location.hash || '').toLowerCase().replace(/^#/, '').replace(/\/$/, '');
            var route = path || hash;
            var is_main_desk = route === '/app' || route === '/app/desk' || route === '/app/home' || route === '/app/modules' || route === '/desk' || route === '/desk/home' || route === '/desk/modules' || route === '';

            // On Task forms, the sub-header bar (Task-Action Buttons.js) provides Back.
            // Hide the floating circle there to avoid duplicate navigation.
            var is_task_form = (document.body.getAttribute('data-route') || '').indexOf('Form/Task') === 0;

            if (!is_mobile || is_main_desk || is_task_form) {
                if (btn) btn.style.display = 'none';
                return;
            }

            if (!btn) {
                btn = document.createElement('div');
                btn.id = 'mobile-back-btn';
                btn.textContent = String.fromCharCode(8592);
                btn.style.cssText = 'position:fixed;bottom:20px;left:20px;width:56px;height:56px;border-radius:50%;background:#1976d2;color:#fff;font-size:30px;display:flex;align-items:center;justify-content:center;box-shadow:0 4px 12px rgba(0,0,0,0.3);z-index:99999;cursor:pointer;user-select:none;-webkit-tap-highlight-color:transparent;touch-action:manipulation;';
                btn.addEventListener('click', function() {
                    if (window.history.length > 1) {
                        history.back();
                    } else {
                        frappe.set_route('List', 'Task');
                    }
                });
                btn.addEventListener('touchstart', function() { this.style.transform = 'scale(0.9)'; });
                btn.addEventListener('touchend', function() { this.style.transform = 'scale(1)'; });
                document.body.appendChild(btn);
            }

            btn.style.display = 'flex';
        }

        buildMobileBackButton();

        if (!window._backBtnWired) {
            window.addEventListener('popstate', function() { setTimeout(buildMobileBackButton, 200); });
            window.addEventListener('hashchange', function() { setTimeout(buildMobileBackButton, 200); });
            window.addEventListener('resize', function() { setTimeout(buildMobileBackButton, 200); });
            document.addEventListener('click', function() {
                setTimeout(buildMobileBackButton, 200);
                setTimeout(buildMobileBackButton, 600);
            });
            if (frappe.router && frappe.router.on) {
                frappe.router.on('change', function() { setTimeout(buildMobileBackButton, 200); });
            }
            window._backBtnWired = true;
        }
    }
});