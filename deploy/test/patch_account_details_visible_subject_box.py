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


def exists(doctype, name):
    try:
        request("GET", f"/api/resource/{enc(doctype)}/{enc(name)}")
        return True
    except RuntimeError as exc:
        if " 404 " in str(exc):
            return False
        raise


def get_doc(doctype, name):
    return request("GET", f"/api/resource/{enc(doctype)}/{enc(name)}")["data"]


def put_doc(doctype, name, payload):
    return request("PUT", f"/api/resource/{enc(doctype)}/{enc(name)}", payload)["data"]


def post_doc(doctype, payload):
    return request("POST", f"/api/resource/{enc(doctype)}", payload)["data"]


def ensure_subject_field():
    name = "Task-custom_account_details_subject"
    payload = {
        "doctype": "Custom Field",
        "name": name,
        "dt": "Task",
        "fieldname": "custom_account_details_subject",
        "label": "Subject",
        "fieldtype": "Data",
        "insert_after": "customer",
        "reqd": 0,
        "hidden": 0,
        "read_only": 0,
    }
    if exists("Custom Field", name):
        put_doc("Custom Field", name, {k: v for k, v in payload.items() if k not in ("doctype", "name")})
        print(f"Updated Custom Field: {name}")
    else:
        post_doc("Custom Field", payload)
        print(f"Created Custom Field: {name}")


def patch_ui_script():
    name = "Task-Account Details UI Cleanup"
    doc = get_doc("Client Script", name)
    script = doc.get("script") or ""

    marker = '''    frm.set_df_property("subject", "reqd", 0);
    frm.set_df_property("subject", "label", "Subject");
    frm.toggle_display("subject", true);
    if (frm.fields_dict.subject && frm.fields_dict.subject.df) {
        frm.fields_dict.subject.df.reqd = 0;
        frm.fields_dict.subject.refresh();
    }'''
    replacement = '''    frm.set_df_property("subject", "reqd", 0);
    frm.toggle_display("subject", false);
    if (frm.fields_dict.subject && frm.fields_dict.subject.df) {
        frm.fields_dict.subject.df.reqd = 0;
    }
    if (frm.fields_dict.custom_account_details_subject) {
        frm.set_df_property("custom_account_details_subject", "label", "Subject");
        frm.set_df_property("custom_account_details_subject", "reqd", 0);
        frm.toggle_display("custom_account_details_subject", true);
        if (!frm.doc.custom_account_details_subject && frm.doc.subject && frm.doc.subject !== "Account Details: Entry" && frm.doc.subject !== "Account Details: Processing") {
            frm.set_value("custom_account_details_subject", frm.doc.subject);
        }
    }'''
    if marker in script:
        script = script.replace(marker, replacement, 1)
    elif replacement not in script:
        fallback = '''    frm.set_df_property("subject", "reqd", 0);'''
        if fallback not in script:
            raise RuntimeError("Expected subject UI block not found")
        script = script.replace(fallback, replacement, 1)

    keep = "fieldname !== 'subject' && fieldname !== 'status'"
    if keep in script and "fieldname !== 'custom_account_details_subject'" not in script:
        script = script.replace(keep, "fieldname !== 'subject' && fieldname !== 'custom_account_details_subject' && fieldname !== 'status'")

    if "custom_account_details_subject(frm)" not in script:
        event_marker = '''    task_kind(frm) {
        task_account_details_ui_cleanup(frm);
    }'''
        event_replacement = '''    task_kind(frm) {
        task_account_details_ui_cleanup(frm);
    },
    custom_account_details_subject(frm) {
        if (["account details", "account details: entry", "account details: processing"].indexOf(String(frm.doc.task_kind || '').trim().toLowerCase()) >= 0) {
            frm.set_value("subject", frm.doc.custom_account_details_subject || frm.doc.subject || "");
        }
    }'''
        if event_marker not in script:
            raise RuntimeError("Expected task_kind event block not found")
        script = script.replace(event_marker, event_replacement, 1)

    put_doc("Client Script", name, {"script": script, "enabled": 1})
    print(f"Updated Client Script: {name}")


def patch_default_assignment():
    name = "Task-Account Details Default Assignment"
    doc = get_doc("Server Script", name)
    script = doc.get("script") or ""
    old = '''    # 1. Keep default subject formatting
    if not doc.get("subject"):
        doc.subject = "Account Details: Entry"'''
    new = '''    # 1. Keep default subject formatting
    if doc.get("custom_account_details_subject"):
        doc.subject = doc.get("custom_account_details_subject")
    elif not doc.get("subject"):
        doc.subject = "Account Details: Entry"'''
    if old in script:
        script = script.replace(old, new, 1)
    elif new not in script:
        raise RuntimeError("Expected default assignment subject block not found")
    put_doc("Server Script", name, {"script": script, "disabled": 0})
    print(f"Updated Server Script: {name}")


def patch_processing_script():
    name = "Task-after-save-account-details-processing"
    doc = get_doc("Server Script", name)
    script = doc.get("script") or ""
    old = 'new_task.subject = doc.subject or "Account Details: Processing"'
    new = 'new_task.subject = doc.get("custom_account_details_subject") or doc.subject or "Account Details: Processing"\n            new_task.custom_account_details_subject = doc.get("custom_account_details_subject") or doc.subject'
    if old in script:
        script = script.replace(old, new, 1)
    elif new not in script:
        raise RuntimeError("Expected Processing subject copy line not found")
    put_doc("Server Script", name, {"script": script, "disabled": 0})
    print(f"Updated Server Script: {name}")


def main():
    print(f"Patching visible Account Details Subject box on TEST only: {BASE_URL}")
    ensure_subject_field()
    patch_ui_script()
    patch_default_assignment()
    patch_processing_script()
    print("Patch complete on TEST. Visible Subject box added and copied from Entry to Processing.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
