// Name: SO-customer-autofill
// DocType: Sales Order
// Enabled: 1
// ---

frappe.ui.form.on('Sales Order', {
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
});