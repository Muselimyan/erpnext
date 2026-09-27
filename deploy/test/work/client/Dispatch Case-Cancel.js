// Name: Dispatch Case-Cancel
// DocType: Dispatch Case
// Enabled: 1
// ---
//
// The Cancel button on the Dispatch Case form. Design:
// deploy/test/work/cancel-flow-design.md
//
// The button appears only when the case can actually be cancelled AND the
// current user is allowed to cancel it. That is a convenience for the user --
// a button that is absent when it cannot be used is better than one that
// explains itself in an error afterwards. It is NOT the protection:
// dispatch_case_cancel enforces both conditions on the server regardless.
//
// Rules mirrored from the server (keep in sync with dispatch_case_cancel.py):
//   cancellable:      Draft, Awaiting Approval, Confirmed, Packed, In Transit
//   before submit:    the order-taker (Order entry task accepter) or Ops - Directors
//   after submit:     Ops - Directors only

var DCC_CANCELLABLE = ["Draft", "Awaiting Approval", "Confirmed", "Packed", "In Transit"];
var DCC_PRE_SUBMIT = ["Draft", "Awaiting Approval"];
var DCC_NEEDS_RETURN = ["Packed", "In Transit"];
var DCC_DIRECTOR_ROLE = "Ops - Directors";
var DCC_REASONS = [
    "Customer cancelled",
    "Surgery cancelled or postponed",
    "Items unavailable",
    "Duplicate order",
    "Entered in error",
    "Other"
];

function dcc_open_dialog(frm) {
    var goods_out = DCC_NEEDS_RETURN.indexOf(frm.doc.status) !== -1;
    var intro = goods_out
        ? __("The goods have left the warehouse. Cancelling raises a Return to warehouse task for the driver, then inspection and restocking bring them back.")
        : __("Nothing has left the warehouse, so no return is needed.");

    var d = new frappe.ui.Dialog({
        title: __("Cancel {0}", [frm.doc.name]),
        fields: [
            {
                fieldtype: "HTML",
                fieldname: "dcc_intro",
                options: "<p>" + frappe.utils.escape_html(intro) + "</p>"
                    + "<p>" + frappe.utils.escape_html(__("All open tasks on this case will be cancelled, and any advance payment tied to it is released to the client's general credit. A cancelled case cannot be reopened.")) + "</p>"
            },
            {
                fieldtype: "Select",
                fieldname: "reason",
                label: __("Reason"),
                options: [""].concat(DCC_REASONS).join("\n"),
                reqd: 1
            },
            {
                fieldtype: "Small Text",
                fieldname: "notes",
                label: __("Notes"),
                description: __("Required when the reason is Other.")
            }
        ],
        primary_action_label: __("Cancel this case"),
        primary_action: function (values) {
            if (values.reason === "Other" && !(values.notes || "").trim()) {
                frappe.msgprint(__("Explain the reason. \"Other\" with no explanation records nothing."));
                return;
            }
            d.get_primary_btn().prop("disabled", true);
            frappe.call({
                method: "dispatch_case_cancel",
                args: {
                    dispatch_case: frm.doc.name,
                    reason: values.reason,
                    notes: values.notes || ""
                },
                freeze: true,
                freeze_message: __("Cancelling {0}...", [frm.doc.name]),
                callback: function (r) {
                    d.hide();
                    var m = (r && r.message) || {};
                    var parts = [__("Case cancelled.")];
                    if ((m.tasks_cancelled || []).length) {
                        parts.push(__("{0} open task(s) cancelled.", [m.tasks_cancelled.length]));
                    }
                    if ((m.credit_released || []).length) {
                        parts.push(__("Advance payment released to general credit."));
                    }
                    if (m.return_task) {
                        parts.push(__("Return raised: {0}.", [m.return_task]));
                    }
                    frappe.show_alert({ message: parts.join(" "), indicator: "orange" }, 7);
                    frm.reload_doc();
                },
                error: function () {
                    // The server's refusal message is shown by Frappe; re-enable
                    // the button so the user can correct the input and retry.
                    d.get_primary_btn().prop("disabled", false);
                }
            });
        }
    });
    d.show();
}

function dcc_add_button(frm) {
    frm.add_custom_button(__("Cancel Case"), function () {
        dcc_open_dialog(frm);
    }).addClass("btn-danger");
}

frappe.ui.form.on("Dispatch Case", {
    refresh: function (frm) {
        if (frm.is_new()) {
            return;
        }
        if (DCC_CANCELLABLE.indexOf(frm.doc.status) === -1) {
            return;
        }
        if (frappe.user.has_role(DCC_DIRECTOR_ROLE)) {
            dcc_add_button(frm);
            return;
        }
        // Before submit, the order-taker may withdraw their own order. They are
        // identified through the case's Order entry task, which in Awaiting
        // Approval is already Completed -- so this reads that task's accepter
        // rather than looking for an open task held by the user.
        if (DCC_PRE_SUBMIT.indexOf(frm.doc.status) === -1 || !frm.doc.order_entry_task) {
            return;
        }
        frappe.db.get_value("Task", frm.doc.order_entry_task, "custom_accepted_by").then(function (r) {
            var accepter = (r && r.message && r.message.custom_accepted_by) || "";
            if (accepter && accepter === frappe.session.user) {
                dcc_add_button(frm);
            }
        });
    }
});
