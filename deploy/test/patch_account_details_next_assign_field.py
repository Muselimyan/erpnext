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
SCRIPT_NAME = "Task-Account Details UI Cleanup"


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


def get_script():
    return request("GET", f"/api/resource/{enc('Client Script')}/{enc(SCRIPT_NAME)}")["data"]


def put_script(script):
    return request("PUT", f"/api/resource/{enc('Client Script')}/{enc(SCRIPT_NAME)}", {"script": script, "enabled": 1})["data"]


def main():
    print(f"Patching Next Task Assign To field on TEST only: {BASE_URL}")
    doc = get_script()
    script = doc.get("script") or ""

    marker = "task_account_details_add_new_accept_button(frm);"
    insert = '''task_account_details_add_new_accept_button(frm);
    if (frm.fields_dict.custom_next_task_assign_to) {
        frm.set_df_property("custom_next_task_assign_to", "label", "Next Task: Assign To");
        frm.toggle_display("custom_next_task_assign_to", true);
    }'''
    if insert not in script:
        if marker not in script:
            raise RuntimeError("Could not find insertion point in Task-Account Details UI Cleanup")
        script = script.replace(marker, insert, 1)

    old_left_filter = "fieldname !== 'status' && fieldname !== 'priority' && fieldname !== 'custom_assigned_to'"
    new_left_filter = "fieldname !== 'status' && fieldname !== 'priority' && fieldname !== 'custom_assigned_to' && fieldname !== 'custom_next_task_assign_to'"
    script = script.replace(old_left_filter, new_left_filter)

    marker_move = "var assignedControl = wrapper.find('[data-fieldname=\"custom_assigned_to\"]').closest('.frappe-control');"
    replacement_move = marker_move + "\n        var nextAssignControl = wrapper.find('[data-fieldname=\"custom_next_task_assign_to\"]').closest('.frappe-control');"
    if "var nextAssignControl = wrapper.find('[data-fieldname=\"custom_next_task_assign_to\"]')" not in script:
        script = script.replace(marker_move, replacement_move, 1)

    marker_append = "if (assignedControl.length) assignedControl.appendTo(leftColumn);"
    replacement_append = marker_append + "\n            if (nextAssignControl.length) nextAssignControl.appendTo(leftColumn);"
    if "if (nextAssignControl.length) nextAssignControl.appendTo(leftColumn);" not in script:
        script = script.replace(marker_append, replacement_append, 1)

    marker_show = "assignedControl.show();"
    replacement_show = marker_show + "\n            nextAssignControl.show();"
    if "nextAssignControl.show();" not in script:
        script = script.replace(marker_show, replacement_show, 1)

    put_script(script)
    print("Updated Client Script: Task-Account Details UI Cleanup")
    print("Patch complete on TEST. Only Next Task: Assign To visibility was changed.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
