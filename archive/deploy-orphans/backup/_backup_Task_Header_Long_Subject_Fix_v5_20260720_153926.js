frappe.ui.form.on('Task', {
    refresh: function(frm) {
        task_header_buttons_layout_v4_diagnostic(frm);
        setTimeout(function() { task_header_buttons_layout_v4_diagnostic(frm); }, 100);
        setTimeout(function() { task_header_buttons_layout_v4_diagnostic(frm); }, 500);
        setTimeout(function() { task_header_buttons_layout_v4_diagnostic(frm); }, 1200);
        setTimeout(function() { task_header_buttons_layout_v4_diagnostic(frm); }, 2500);
    }
});

function task_header_buttons_layout_v4_diagnostic(frm) {
    var styleId = 'task-header-buttons-layout-v4-diagnostic';
    var existingStyle = document.getElementById(styleId);
    if (existingStyle) existingStyle.remove();

    var style = document.createElement('style');
    style.id = styleId;
    style.textContent = `
/* CRITICAL: Force page-head to be relative container */
.page-head,
body .page-head,
html body .page-head,
.layout-main .page-head,
.layout-main-section .page-head {
    position: relative !important;
    overflow: visible !important;
    min-height: 40px !important;
}

/* CRITICAL: page-head-content must allow absolute positioning inside */
.page-head .page-head-content,
body .page-head .page-head-content,
html body .page-head .page-head-content,
.layout-main .page-head .page-head-content {
    position: relative !important;
    min-width: 0 !important;
    max-width: 100% !important;
    overflow: visible !important;
    padding-right: 440px !important;
    min-height: 38px !important;
}

/* Title area: must stay within left space */
.page-head .title-area,
body .page-head .title-area,
html body .page-head .title-area {
    min-width: 0 !important;
    max-width: 100% !important;
    overflow: hidden !important;
    flex: 1 1 auto !important;
}

/* Title text: truncate with ellipsis */
.page-head .title-text,
body .page-head .title-text,
html body .page-head .title-text,
.page-head .title-text a,
.page-head .title-text span,
.page-head .ellipsis,
.page-head h3 {
    display: block !important;
    min-width: 0 !important;
    max-width: 100% !important;
    overflow: hidden !important;
    text-overflow: ellipsis !important;
    white-space: nowrap !important;
    word-break: normal !important;
}

/* Breadcrumb: also truncate */
.page-head .breadcrumb,
body .page-head .breadcrumb,
.page-head .breadcrumb-item,
.page-head .breadcrumb-item a {
    min-width: 0 !important;
    max-width: 100% !important;
    overflow: hidden !important;
    text-overflow: ellipsis !important;
    white-space: nowrap !important;
}

/* CRITICAL: Fix page-actions to top-right */
.page-head .page-actions,
body .page-head .page-actions,
html body .page-head .page-actions,
.layout-main .page-head .page-actions {
    position: absolute !important;
    top: 0 !important;
    right: 0 !important;
    width: 430px !important;
    max-width: 430px !important;
    min-width: 430px !important;
    display: flex !important;
    flex-wrap: wrap !important;
    justify-content: flex-end !important;
    align-items: flex-start !important;
    gap: 4px !important;
    z-index: 200 !important;
    overflow: visible !important;
    background: var(--bg-color, #ffffff) !important;
    padding: 0 !important;
    margin: 0 !important;
}

/* Standard/custom actions inside page-actions */
.page-head .page-actions .standard-actions,
.page-head .page-actions .custom-actions,
body .page-head .page-actions .standard-actions,
body .page-head .page-actions .custom-actions {
    display: flex !important;
    flex-wrap: wrap !important;
    justify-content: flex-end !important;
    align-items: flex-start !important;
    gap: 4px !important;
    min-width: 0 !important;
    max-width: 100% !important;
}

/* Buttons: prevent overflow */
.page-head .page-actions .btn,
body .page-head .page-actions .btn,
.page-head .standard-actions .btn,
.page-head .custom-actions .btn {
    flex: 0 0 auto !important;
    max-width: 180px !important;
    overflow: hidden !important;
    text-overflow: ellipsis !important;
    white-space: nowrap !important;
}

/* Responsive: on narrow screens, move buttons below title */
@media (max-width: 1280px) {
    .page-head .page-head-content,
    body .page-head .page-head-content {
        padding-right: 0 !important;
        padding-bottom: 42px !important;
    }
    .page-head .page-actions,
    body .page-head .page-actions {
        position: static !important;
        width: 100% !important;
        max-width: 100% !important;
        min-width: 0 !important;
        justify-content: flex-start !important;
        margin-top: 8px !important;
        background: transparent !important;
    }
    .page-head .page-actions .standard-actions,
    .page-head .page-actions .custom-actions {
        justify-content: flex-start !important;
    }
}
`;
    document.head.appendChild(style);

    // Diagnostic logging
    if (frm && frm.page && frm.page.wrapper) {
        var wrapper = $(frm.page.wrapper);
        var pageHead = wrapper.find('.page-head');
        var pageHeadContent = pageHead.find('.page-head-content');
        var titleArea = pageHead.find('.title-area');
        var pageActions = pageHead.find('.page-actions');
        
        console.log('[TaskHeaderFix] Diagnostic:', {
            pageHead: pageHead.length,
            pageHeadContent: pageHeadContent.length,
            titleArea: titleArea.length,
            pageActions: pageActions.length,
            pageActionsPosition: pageActions.css('position'),
            pageActionsTop: pageActions.css('top'),
            pageActionsRight: pageActions.css('right'),
            pageHeadContentPaddingRight: pageHeadContent.css('padding-right')
        });

        // Force tooltip on title
        var titleText = titleArea.find('.title-text').first();
        if (titleText.length) {
            var fullText = $.trim(titleText.text());
            if (fullText) titleText.attr('title', fullText);
        }
    }
}
