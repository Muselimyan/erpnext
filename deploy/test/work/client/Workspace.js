// Name: Workspace
// DocType: Workspace
// Enabled: 1
// ---

frappe.ui.form.on('Workspace', {
    refresh: function(frm) {
        if (frm.doc.name === 'Home') {
            setTimeout(() => {
                inject_clean_grid_shortcut();
            }, 300);
        }
    }
});

function inject_clean_grid_shortcut() {
    if ($("#custom-task-grid-shortcut").length > 0) return;
    let gridContainer = $(".desk-container .desk-section [data-widget-type='shortcut']").parent();
    if (!gridContainer.length) {
        gridContainer = $(".desk-section .grid-container, .desk-container .desk-section");
    }
    if (gridContainer.length) {
        let customIconHtml = '<div id="custom-task-grid-shortcut" class="widget-widget-box" style="cursor:pointer;min-width:140px;margin:15px;text-align:center;" onclick="frappe.set_route(\'List\',\'Task\')"><div class="widget-head" style="display:flex;flex-direction:column;align-items:center;justify-content:center;gap:10px;"><div class="shortcut-icon-wrapper" style="width:72px;height:72px;background-color:#eff6ff;border-radius:16px;display:flex;align-items:center;justify-content:center;box-shadow:0 4px 6px -1px rgba(0,0,0,0.05);transition:transform 0.2s ease;"><svg class="icon" style="width:32px;height:32px;stroke:#2563eb;fill:none;stroke-width:2;"><use href="#icon-ticket"></use></svg></div><span class="widget-title-link" style="font-size:13px;font-weight:500;color:#1f2937;margin-top:4px;display:block;">Task List</span></div></div>';
        gridContainer.append(customIconHtml);
        $("#custom-task-grid-shortcut").hover(
            function() { $(this).find(".shortcut-icon-wrapper").css("transform","translateY(-3px)"); },
            function() { $(this).find(".shortcut-icon-wrapper").css("transform","translateY(0)"); }
        );
    }
}