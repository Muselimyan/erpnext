frappe.ui.form.on('Task', {
    refresh: function(frm) {
        task_mobile_form_layout_fix(frm);
        setTimeout(function() { task_mobile_form_layout_fix(frm); }, 250);
        setTimeout(function() { task_mobile_form_layout_fix(frm); }, 900);
    },
    after_save: function(frm) {
        setTimeout(function() { task_mobile_form_layout_fix(frm); }, 500);
    }
});

function task_mobile_form_layout_fix(frm) {
    if (window.innerWidth > 768) return;

    if (!document.getElementById('task-mobile-form-layout-fix-style')) {
        var style = document.createElement('style');
        style.id = 'task-mobile-form-layout-fix-style';
        style.textContent = `
@media (max-width: 768px) {
    body[data-route^="Form/Task"] .page-head {
        overflow: visible !important;
        min-height: 86px !important;
    }
    body[data-route^="Form/Task"] .page-head .container,
    body[data-route^="Form/Task"] .page-head .container-fluid,
    body[data-route^="Form/Task"] .page-head .page-head-content {
        width: 100% !important;
        max-width: 100% !important;
        min-width: 0 !important;
        overflow: visible !important;
    }
    body[data-route^="Form/Task"] .page-head .page-head-content {
        display: grid !important;
        grid-template-columns: minmax(0, 1fr) auto !important;
        grid-template-areas: "title title" "actions actions" !important;
        align-items: start !important;
        gap: 4px !important;
        min-height: 78px !important;
        padding-top: 4px !important;
        padding-bottom: 6px !important;
    }
    body[data-route^="Form/Task"] .page-head .title-area {
        grid-area: title !important;
        min-width: 0 !important;
        width: 100% !important;
        max-width: 100% !important;
        overflow: visible !important;
    }
    body[data-route^="Form/Task"] .page-head .title-text,
    body[data-route^="Form/Task"] .page-head .title-text a,
    body[data-route^="Form/Task"] .page-head .title-text span,
    body[data-route^="Form/Task"] .page-head h3,
    body[data-route^="Form/Task"] .page-head .ellipsis {
        display: -webkit-box !important;
        -webkit-line-clamp: 2 !important;
        -webkit-box-orient: vertical !important;
        white-space: normal !important;
        overflow: hidden !important;
        text-overflow: ellipsis !important;
        overflow-wrap: anywhere !important;
        word-break: break-word !important;
        line-height: 1.18 !important;
        max-height: 2.4em !important;
        max-width: 100% !important;
    }
    body[data-route^="Form/Task"] .page-head .page-actions,
    body[data-route^="Form/Task"] .page-head .standard-actions,
    body[data-route^="Form/Task"] .page-head .custom-actions {
        grid-area: actions !important;
        width: 100% !important;
        max-width: 100% !important;
        min-width: 0 !important;
        margin-left: 0 !important;
        display: flex !important;
        flex-wrap: nowrap !important;
        align-items: center !important;
        justify-content: flex-end !important;
        gap: 4px !important;
        overflow-x: auto !important;
        overflow-y: hidden !important;
        -webkit-overflow-scrolling: touch !important;
        scrollbar-width: none !important;
    }
    body[data-route^="Form/Task"] .page-head .page-actions::-webkit-scrollbar,
    body[data-route^="Form/Task"] .page-head .standard-actions::-webkit-scrollbar,
    body[data-route^="Form/Task"] .page-head .custom-actions::-webkit-scrollbar {
        display: none !important;
    }
    body[data-route^="Form/Task"] .page-head .page-actions .btn,
    body[data-route^="Form/Task"] .page-head .standard-actions .btn,
    body[data-route^="Form/Task"] .page-head .custom-actions .btn {
        flex: 0 0 auto !important;
        max-width: 86px !important;
        padding: 4px 7px !important;
        font-size: 12px !important;
        line-height: 1.2 !important;
        overflow: hidden !important;
        text-overflow: ellipsis !important;
        white-space: nowrap !important;
    }
    body[data-route^="Form/Task"] .form-tabs-list,
    body[data-route^="Form/Task"] .form-tabs {
        overflow-x: auto !important;
        overflow-y: hidden !important;
        flex-wrap: nowrap !important;
        white-space: nowrap !important;
    }
    body[data-route^="Form/Task"] [data-fieldname="subject"],
    body[data-route^="Form/Task"] [data-fieldname="subject"] .control-input-wrapper,
    body[data-route^="Form/Task"] [data-fieldname="subject"] .control-input {
        display: block !important;
        visibility: visible !important;
    }
    body[data-route^="Form/Task"] [data-fieldname="subject"] input,
    body[data-route^="Form/Task"] [data-fieldname="subject"] textarea {
        min-height: 38px !important;
        font-size: 15px !important;
    }
    body[data-route^="Form/Task"] .form-page {
        padding-bottom: 92px !important;
    }
}
`;
        document.head.appendChild(style);
    }

    try {
        if (frm && frm.fields_dict && frm.fields_dict.subject) {
            frm.toggle_display('subject', true);
            frm.set_df_property('subject', 'hidden', 0);
            frm.set_df_property('subject', 'reqd', 0);
        }
        $(frm.wrapper).find('[data-fieldname="subject"]').closest('.frappe-control').show().css({ display: 'block', visibility: 'visible' });
        var titleText = document.querySelector('body[data-route^="Form/Task"] .page-head .title-text');
        if (titleText) {
            var fullText = titleText.textContent.trim();
            if (fullText) titleText.setAttribute('title', fullText);
        }
    } catch (e) {}
}
