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


def patch_ui():
    name = "Task-Account Details UI Cleanup"
    doc = get_doc("Client Script", name)
    script = doc.get("script") or ""

    marker = '''    frm.set_df_property("subject", "reqd", 0);
    frm.toggle_display("subject", true);
    if (frm.fields_dict.subject && frm.fields_dict.subject.df) {
        frm.fields_dict.subject.df.reqd = 0;
    }'''
    replacement = '''    frm.set_df_property("subject", "reqd", 0);
    frm.set_df_property("subject", "label", "Subject");
    frm.toggle_display("subject", true);
    if (frm.fields_dict.subject && frm.fields_dict.subject.df) {
        frm.fields_dict.subject.df.reqd = 0;
        frm.fields_dict.subject.refresh();
    }'''
    if marker in script:
        script = script.replace(marker, replacement, 1)
    elif replacement not in script:
        raise RuntimeError("Expected subject UI block not found")

    old_filter = "fieldname !== 'status' && fieldname !== 'priority' && fieldname !== 'custom_assigned_to' && fieldname !== 'custom_next_task_assign_to'"
    new_filter = "fieldname !== 'subject' && fieldname !== 'status' && fieldname !== 'priority' && fieldname !== 'custom_assigned_to' && fieldname !== 'custom_next_task_assign_to'"
    script = script.replace(old_filter, new_filter)

    assign_line = '''var assignedControl = wrapper.find('[data-fieldname="custom_assigned_to"]').closest('.frappe-control');'''
    subject_line = assign_line + '''
        var subjectControl = wrapper.find('[data-fieldname="subject"]').closest('.frappe-control');'''
    if "var subjectControl = wrapper.find('[data-fieldname=\"subject\"]')" not in script:
        script = script.replace(assign_line, subject_line, 1)

    append_line = '''if (statusControl.length) {
            var completeBtn = statusControl.find('#complete-task-btn').detach();'''
    append_replacement = '''if (statusControl.length) {
            var completeBtn = statusControl.find('#complete-task-btn').detach();
            if (subjectControl.length) subjectControl.appendTo(leftColumn);'''
    if "if (subjectControl.length) subjectControl.appendTo(leftColumn);" not in script:
        script = script.replace(append_line, append_replacement, 1)

    show_line = '''statusControl.show();
            priorityControl.show();'''
    show_replacement = '''subjectControl.show();
            statusControl.show();
            priorityControl.show();'''
    if "subjectControl.show();" not in script:
        script = script.replace(show_line, show_replacement, 1)

    put_doc("Client Script", name, {"script": script, "enabled": 1})
    print(f"Updated Client Script: {name}")


def patch_server():
    name = "Task-after-save-account-details-processing"
    doc = get_doc("Server Script", name)
    script = doc.get("script") or ""
    old = 'new_task.subject = "Account Details: Processing"'
    new = 'new_task.subject = doc.subject or "Account Details: Processing"'
    if old in script:
        script = script.replace(old, new, 1)
    elif new not in script:
        raise RuntimeError("Expected Processing subject assignment not found")
    put_doc("Server Script", name, {"script": script, "disabled": 0})
    print(f"Updated Server Script: {name}")


def main():
    print(f"Patching Account Details optional subject and subject copy on TEST only: {BASE_URL}")
    patch_ui()
    patch_server()
    print("Patch complete on TEST. Subject is optional and Entry subject is copied to Processing.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
