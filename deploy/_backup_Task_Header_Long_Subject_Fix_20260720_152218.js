frappe.ui.form.on('Task', {
    refresh: function(frm) {
        task_header_subject_clamp_fix();
    }
});

function task_header_subject_clamp_fix() {
    if (document.getElementById('task-header-subject-clamp-fix')) return;
    var style = document.createElement('style');
    style.id = 'task-header-subject-clamp-fix';
    style.textContent = `
/* Desktop: ensure page head content wraps properly */
body[data-route^="Form/Task"] .page-head .container,
body[data-route^="Form/Task"] .page-head .container-fluid,
body[data-route^="Form/Task"] .page-head .page-head-content {
    min-width: 0 !important;
}

/* Flex layout: title area + buttons */
body[data-route^="Form/Task"] .page-head .page-head-content {
    display: flex !important;
    align-items: flex-start !important;
    gap: 12px !important;
    flex-wrap: wrap !important;
}

/* Title area: flexible, can shrink */
body[data-route^="Form/Task"] .page-head .title-area {
    min-width: 0 !important;
    flex: 1 1 auto !important;
    max-width: 100% !important;
    overflow: hidden !important;
}

/* Subject text: clamp to 2 lines, show ellipsis */
body[data-route^="Form/Task"] .page-head .title-text,
body[data-route^="Form/Task"] .page-head .title-text a,
body[data-route^="Form/Task"] .page-head .title-text span,
body[data-route^="Form/Task"] .page-head h3 {
    display: -webkit-box !important;
    -webkit-line-clamp: 2 !important;
    -webkit-box-orient: vertical !important;
    overflow: hidden !important;
    text-overflow: ellipsis !important;
    word-break: break-word !important;
    line-height: 1.3 !important;
    max-height: 2.6em !important;
}

/* Buttons: fixed on the right, always visible */
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

/* Add full subject as title attribute for tooltip */
body[data-route^="Form/Task"] .page-head .title-text {
    cursor: help !important;
}
`;
    document.head.appendChild(style);
    
    // Add full subject as tooltip
    setTimeout(function() {
        var titleText = document.querySelector('body[data-route^="Form/Task"] .page-head .title-text');
        if (titleText && !titleText.hasAttribute('title')) {
            var fullText = titleText.textContent.trim();
            if (fullText) {
                titleText.setAttribute('title', fullText);
            }
        }
    }, 500);
}
