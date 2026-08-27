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
    var is_pack_task = !!(frm && frm.doc && frm.doc.task_kind === 'Pack / prepare items');
    document.body.classList.toggle('task-mobile-pack-clean', is_pack_task);

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
    body.task-mobile-pack-clean[data-route^="Form/Task"] .task-mobile-pack-hidden {
        display: none !important;
    }
    body.task-mobile-pack-clean[data-route^="Form/Task"] .task-mobile-pack-summary {
        margin: 8px 0 12px 0 !important;
        padding: 10px 12px !important;
        border: 1px solid var(--border-color, #d1d8dd) !important;
        border-radius: 10px !important;
        background: #f8fafc !important;
        color: var(--text-color, #192734) !important;
        box-shadow: 0 1px 2px rgba(0,0,0,0.04) !important;
    }
    body.task-mobile-pack-clean[data-route^="Form/Task"] .task-mobile-pack-summary-title {
        display: block !important;
        font-size: 16px !important;
        font-weight: 700 !important;
        line-height: 1.25 !important;
        overflow-wrap: anywhere !important;
    }
    body.task-mobile-pack-clean[data-route^="Form/Task"] .task-mobile-pack-summary-meta {
        display: block !important;
        margin-top: 4px !important;
        color: var(--text-muted, #6c7680) !important;
        font-size: 12px !important;
        line-height: 1.3 !important;
        overflow-wrap: anywhere !important;
    }
    body.task-mobile-pack-clean[data-route^="Form/Task"] [data-fieldname="subject"] {
        margin-top: 4px !important;
    }
    body.task-mobile-pack-clean[data-route^="Form/Task"] .section-head,
    body.task-mobile-pack-clean[data-route^="Form/Task"] .control-label {
        font-size: 14px !important;
    }
    body.task-mobile-pack-clean[data-route^="Form/Task"] .frappe-control {
        margin-bottom: 12px !important;
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

        if (is_pack_task && frm && frm.wrapper) {
            task_mobile_pack_cleanup(frm);
        }
    } catch (e) {}
}

function task_mobile_pack_cleanup(frm) {
    var $w = $(frm.wrapper);
    var subject = (frm.doc.subject || '').trim();
    var dispatch_case = (frm.doc.dispatch_case || '').trim();
    var status = (frm.doc.dispatch_case_status || frm.doc.custom_dispatch_case_status || '').trim();
    var customer = (frm.doc.customer || '').trim();

    var $target = $w.find('.form-layout').first();
    if (!$target.length) $target = $w.find('.layout-main-section').first();
    if ($target.length && (subject || dispatch_case || status || customer)) {
        var $summary = $w.find('.task-mobile-pack-summary');
        if (!$summary.length) {
            $summary = $('<div class="task-mobile-pack-summary"><span class="task-mobile-pack-summary-title"></span><span class="task-mobile-pack-summary-meta"></span></div>');
            $target.prepend($summary);
        }
        $summary.find('.task-mobile-pack-summary-title').text(subject || 'Pack Task');
        var meta = [];
        if (dispatch_case) meta.push('Dispatch Case: ' + dispatch_case);
        if (status) meta.push('Status: ' + status);
        if (customer) meta.push('Customer: ' + customer);
        $summary.find('.task-mobile-pack-summary-meta').text(meta.join(' | '));
    }

    var hide_fields = [
        'completed_at',
        'task_kind',
        'custom_assigned_to',
        'custom_next_task_assign_to',
        'custom_accepted_at',
        'accepted_at'
    ];
    hide_fields.forEach(function(fieldname) {
        $w.find('[data-fieldname="' + fieldname + '"]').closest('.frappe-control').addClass('task-mobile-pack-hidden');
    });

    $w.find('[data-fieldname="customer"]').each(function() {
        var $control = $(this).closest('.frappe-control');
        var value = ($control.find('input, textarea').val() || $control.find('.control-value').text() || '').trim();
        $control.toggleClass('task-mobile-pack-hidden', !value);
    });

    $w.find('[data-fieldname="subject"]').each(function() {
        $(this).closest('.frappe-control').addClass('task-mobile-pack-hidden');
    });

    $w.find('[data-fieldname="dispatch_case"]').closest('.frappe-control').removeClass('task-mobile-pack-hidden');
    $w.find('[data-fieldname="custom_product_lines"], [data-fieldname="custom_task_product_work"], [data-fieldname="custom_packing_items"]').closest('.frappe-control').removeClass('task-mobile-pack-hidden');
}
