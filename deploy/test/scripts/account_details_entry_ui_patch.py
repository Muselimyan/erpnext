import json
import sys
import urllib.parse
import urllib.request
import urllib.error

BASE_URL = "https://test.erpnext.am"
AUTH = "token af78cbd691f0b2e:b26698573b80f5e"
HEADERS = {
    "Authorization": AUTH,
    "Content-Type": "application/json",
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ERPNextPatch/1.0",
}


def enc(value):
    return urllib.parse.quote(value, safe="")


def request(method, path, payload=None):
    data = None
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(BASE_URL + path, data=data, headers=HEADERS, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as res:
            raw = res.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        raise RuntimeError(f"{method} {path} failed: {e.code} {body[:1200]}") from e


def get_doc(doctype, name):
    return request("GET", f"/api/resource/{enc(doctype)}/{enc(name)}")["data"]


def put_doc(doctype, name, payload):
    return request("PUT", f"/api/resource/{enc(doctype)}/{enc(name)}", payload)["data"]


def list_docs(doctype):
    fields = enc(json.dumps(["name", "dt", "enabled", "modified"]))
    return request("GET", f"/api/resource/{enc(doctype)}?fields={fields}&limit_page_length=500")["data"]


def find_task_accept_script():
    matches = []
    for row in list_docs("Client Script"):
        doc = get_doc("Client Script", row["name"])
        script = doc.get("script") or ""
        if doc.get("dt") == "Task" and "Accept / Start Task" in script and "operationalKinds" in script:
            matches.append(doc)
    if not matches:
        raise RuntimeError("Could not find Task client script with Accept / Start Task and operationalKinds")
    if len(matches) > 1:
        print("Multiple matching scripts found; using first:")
        for m in matches:
            print(" -", m["name"])
    return matches[0]


def main():
    print(f"Applying Account Details Entry UI patch to TEST only: {BASE_URL}")
    doc = find_task_accept_script()
    name = doc["name"]
    script = doc.get("script") or ""

    script = script.replace('"Account details",', '"Account Details: Entry", "Account Details: Processing",')
    script = script.replace('"Account details"', '"Account Details: Entry"')

    helper_marker = "function account_details_entry_ui_cleanup(frm)"
    helper = r'''
function account_details_entry_ui_cleanup(frm) {
    if (frm.doc.task_kind !== "Account Details: Entry") return;

    var hideFields = [
        "custom_task_scan_barcode",
        "custom_task_scan_qty",
        "custom_task_choose_product",
        "custom_task_product_qty",
        "custom_task_add_batch_no",
        "custom_task_add_unit_price",
        "custom_warehouse_pickup_photo",
        "custom_warehouse_drop_off_photo",
        "custom_warehouse_dropoff_photo",
        "custom_pickup_photo",
        "custom_drop_off_photo",
        "custom_dropoff_photo"
    ];

    hideFields.forEach(function(fieldname) {
        if (frm.fields_dict[fieldname]) {
            frm.toggle_display(fieldname, false);
            frm.set_df_property(fieldname, "hidden", 1);
        }
        $(frm.wrapper).find('[data-fieldname="' + fieldname + '"]').closest('.frappe-control').hide();
    });

    ["status", "priority"].forEach(function(fieldname) {
        if (frm.fields_dict[fieldname]) frm.toggle_display(fieldname, true);
    });

    if (frm.fields_dict.custom_account_photos) {
        frm.toggle_display("custom_account_photos", true);
    }

    setTimeout(function() {
        [
            "Barcode Scanning (Optional)",
            "Scan Product Barcode",
            "Scan Qty",
            "Choose Product",
            "Product Qty",
            "Batch / LOT",
            "Unit Price",
            "Warehouse Pickup Photo",
            "Warehouse Drop-off Photo"
        ].forEach(function(label) {
            $(frm.wrapper).find('.section-head').filter(function() { return $(this).text().trim() === label; }).closest('.form-section').hide();
            $(frm.wrapper).find('.control-label, label').filter(function() { return $(this).text().trim() === label; }).closest('.frappe-control').hide();
        });
    }, 300);

    $(frm.wrapper).find("#account-details-add-photos-btn").remove();
    var anchor = frm.fields_dict.custom_account_photos || frm.fields_dict.customer || frm.fields_dict.priority;
    if (anchor && anchor.$wrapper) {
        var addPhotos = $('<button id="account-details-add-photos-btn" class="btn btn-default btn-sm" style="margin-top:8px;margin-bottom:12px;display:block;">Add Photos</button>');
        addPhotos.on("click", function() {
            var runUploader = function() {
                frappe.call({
                    method: "frappe.client.get_count",
                    args: { doctype: "File", filters: { attached_to_doctype: "Task", attached_to_name: frm.doc.name } },
                    callback: function(r) {
                        var existing = r.message || 0;
                        if (existing >= 5) {
                            frappe.msgprint("Maximum 5 photos/files can be attached.");
                            return;
                        }
                        new frappe.ui.FileUploader({
                            doctype: "Task",
                            docname: frm.doc.name,
                            folder: "Home/Attachments",
                            allow_multiple: true,
                            restrictions: { allowed_file_types: ["image/*"] },
                            on_success: function() { frm.reload_doc(); }
                        });
                    }
                });
            };
            if (frm.is_new() || frm.dirty()) {
                frm.save().then(runUploader);
            } else {
                runUploader();
            }
        });
        anchor.$wrapper.after(addPhotos);
    }
}
'''
    if helper_marker in script:
        start = script.index(helper_marker)
        end_marker = "\n}\n\nfrappe.ui.form.on"
        end = script.find(end_marker, start)
        if end != -1:
            script = script[:start] + helper.strip() + script[end + 3:]
    else:
        script = helper + "\n" + script

    script = script.replace('        account_details_entry_ui_cleanup(frm);\n', '')
    refresh_marker = '    refresh(frm) {\n'
    if refresh_marker in script:
        script = script.replace(refresh_marker, refresh_marker + '        account_details_entry_ui_cleanup(frm);\n', 1)
    else:
        raise RuntimeError('Could not find refresh(frm) handler in Task-Accept Start')

    script = script.replace('if (!frm.is_new() && operationalKinds.includes(frm.doc.task_kind) && ["Open", "Working"].includes(frm.doc.status) && frm.doc.custom_accepted_by !== frappe.session.user) {', 'if (((!frm.is_new()) || frm.doc.task_kind === "Account Details: Entry") && operationalKinds.includes(frm.doc.task_kind) && ["Open", "Working"].includes(frm.doc.status) && frm.doc.custom_accepted_by !== frappe.session.user) {')

    put_doc("Client Script", name, {"script": script, "enabled": 1})
    print(f"Updated Client Script: {name}")
    print("Patch complete on TEST. No other scripts changed.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
