# -*- coding: utf-8 -*-
"""
deploy_so_client_script.py
Create/update a Client Script on Sales Order that auto-fills
hospital and doctor_name when a customer is selected.
"""
import frappe

SCRIPT_NAME = "SO-customer-autofill"

SCRIPT = """frappe.ui.form.on('Sales Order', {
    customer(frm) {
        if (!frm.doc.customer) {
            frm.set_value('hospital', '');
            frm.set_value('doctor_name', '');
            return;
        }
        frappe.db.get_value('Customer', frm.doc.customer,
            ['client_kind', 'hospital', 'doctor_name'],
            (r) => {
                if (!r) return;
                if (r.client_kind === 'Hospital') {
                    frm.set_value('hospital',    frm.doc.customer);
                    frm.set_value('doctor_name', '');
                } else {
                    frm.set_value('hospital',    r.hospital    || '');
                    frm.set_value('doctor_name', r.doctor_name || '');
                }
            }
        );
    }
});"""

existing = frappe.db.exists("Client Script", SCRIPT_NAME)
if existing:
    doc = frappe.get_doc("Client Script", SCRIPT_NAME)
    doc.script  = SCRIPT
    doc.enabled = 1
    doc.save(ignore_permissions=True)
    print(f"Updated: {SCRIPT_NAME!r}")
else:
    frappe.get_doc({
        "doctype": "Client Script",
        "name":    SCRIPT_NAME,
        "dt":      "Sales Order",
        "view":    "Form",
        "enabled": 1,
        "script":  SCRIPT,
    }).insert(ignore_permissions=True)
    print(f"Created: {SCRIPT_NAME!r}")

frappe.db.commit()
print("Done.")
