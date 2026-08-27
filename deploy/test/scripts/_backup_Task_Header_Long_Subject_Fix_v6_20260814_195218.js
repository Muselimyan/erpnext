frappe.ui.form.on('Task', {
    refresh: function(frm) {
        task_header_long_subject_fix();
    }
});

function task_header_long_subject_fix() {
    if (document.getElementById('task-header-long-subject-fix')) return;
    var style = document.createElement('style');
    style.id = 'task-header-long-subject-fix';
    style.textContent = `
body[data-route^="Form/Task"] .page-head .container,
body[data-route^="Form/Task"] .page-head .container-fluid,
body[data-route^="Form/Task"] .page-head .page-head-content,
body[data-route^="Form/Task"] .page-head .standard-actions {
    min-width: 0 !important;
}
body[data-route^="Form/Task"] .page-head .page-head-content {
    display: flex !important;
    align-items: flex-start !important;
    gap: 8px !important;
    flex-wrap: nowrap !important;
}
body[data-route^="Form/Task"] .page-head .title-area {
    min-width: 0 !important;
    flex: 1 1 auto !important;
    max-width: none !important;
    overflow: visible !important;
}
body[data-route^="Form/Task"] .page-head .title-text,
body[data-route^="Form/Task"] .page-head .title-text a,
body[data-route^="Form/Task"] .page-head .title-text span,
body[data-route^="Form/Task"] .page-head h3,
body[data-route^="Form/Task"] .page-head .ellipsis {
    white-space: normal !important;
    overflow-wrap: anywhere !important;
    word-break: break-word !important;
    overflow: visible !important;
    text-overflow: clip !important;
    line-height: 1.25 !important;
    max-width: 100% !important;
}
body[data-route^="Form/Task"] .page-head .page-actions,
body[data-route^="Form/Task"] .page-head .standard-actions,
body[data-route^="Form/Task"] .page-head .custom-actions {
    flex: 0 0 auto !important;
    white-space: nowrap !important;
    display: flex !important;
    align-items: flex-start !important;
    justify-content: flex-end !important;
    min-width: max-content !important;
    margin-left: auto !important;
    position: relative !important;
    z-index: 2 !important;
}
body[data-route^="Form/Task"] .page-head .page-actions .btn,
body[data-route^="Form/Task"] .page-head .standard-actions .btn,
body[data-route^="Form/Task"] .page-head .custom-actions .btn {
    flex: 0 0 auto !important;
}
`;
    document.head.appendChild(style);
}
