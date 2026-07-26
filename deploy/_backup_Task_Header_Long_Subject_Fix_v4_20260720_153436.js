frappe.ui.form.on('Task', {
    refresh: function(frm) {
        task_header_buttons_layout_v3(frm);
        setTimeout(function() { task_header_buttons_layout_v3(frm); }, 200);
        setTimeout(function() { task_header_buttons_layout_v3(frm); }, 800);
        setTimeout(function() { task_header_buttons_layout_v3(frm); }, 1500);
    }
});

function task_header_buttons_layout_v3(frm) {
    if (!document.getElementById('task-header-buttons-layout-v3')) {
        var style = document.createElement('style');
        style.id = 'task-header-buttons-layout-v3';
        style.textContent = `
body[data-route^="Form/Task"] .page-head {
    overflow: visible !important;
}
body[data-route^="Form/Task"] .page-head .container,
body[data-route^="Form/Task"] .page-head .container-fluid,
body[data-route^="Form/Task"] .page-head .page-head-content {
    position: relative !important;
    min-width: 0 !important;
    max-width: 100% !important;
    overflow: visible !important;
}
body[data-route^="Form/Task"] .page-head .page-head-content {
    min-height: 34px !important;
    padding-right: 430px !important;
}
body[data-route^="Form/Task"] .page-head .title-area,
body[data-route^="Form/Task"] .page-head .title-area .title-text,
body[data-route^="Form/Task"] .page-head .title-area .ellipsis,
body[data-route^="Form/Task"] .page-head .breadcrumb,
body[data-route^="Form/Task"] .page-head .breadcrumb-item,
body[data-route^="Form/Task"] .page-head .breadcrumb-item a {
    min-width: 0 !important;
    max-width: 100% !important;
    overflow: hidden !important;
    text-overflow: ellipsis !important;
    white-space: nowrap !important;
}
body[data-route^="Form/Task"] .page-head .page-actions {
    position: absolute !important;
    top: 0 !important;
    right: 0 !important;
    width: 420px !important;
    max-width: 420px !important;
    min-width: 420px !important;
    display: flex !important;
    flex-wrap: wrap !important;
    justify-content: flex-end !important;
    align-items: flex-start !important;
    gap: 4px !important;
    z-index: 100 !important;
    overflow: visible !important;
    background: var(--bg-color, #fff) !important;
}
body[data-route^="Form/Task"] .page-head .standard-actions,
body[data-route^="Form/Task"] .page-head .custom-actions {
    display: flex !important;
    flex-wrap: wrap !important;
    justify-content: flex-end !important;
    align-items: flex-start !important;
    gap: 4px !important;
    min-width: 0 !important;
    max-width: 100% !important;
}
body[data-route^="Form/Task"] .page-head .page-actions .btn,
body[data-route^="Form/Task"] .page-head .standard-actions .btn,
body[data-route^="Form/Task"] .page-head .custom-actions .btn {
    flex: 0 0 auto !important;
    max-width: 175px !important;
    overflow: hidden !important;
    text-overflow: ellipsis !important;
    white-space: nowrap !important;
}
@media (max-width: 1250px) {
    body[data-route^="Form/Task"] .page-head .page-head-content {
        padding-right: 0 !important;
        padding-bottom: 34px !important;
    }
    body[data-route^="Form/Task"] .page-head .page-actions {
        position: static !important;
        width: 100% !important;
        max-width: 100% !important;
        min-width: 0 !important;
        justify-content: flex-start !important;
        margin-top: 6px !important;
        background: transparent !important;
    }
    body[data-route^="Form/Task"] .page-head .standard-actions,
    body[data-route^="Form/Task"] .page-head .custom-actions {
        justify-content: flex-start !important;
    }
}
`;
        document.head.appendChild(style);
    }

    var pageHead = frm && frm.page && frm.page.wrapper ? $(frm.page.wrapper).find('.page-head') : $('.page-head');
    var titleText = pageHead.find('.title-text').first();
    if (titleText.length) {
        var fullText = $.trim(titleText.text());
        if (fullText) titleText.attr('title', fullText);
    }
}
