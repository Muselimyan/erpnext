import json
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE_URL = "https://test.erpnext.am"
API_KEY = "af78cbd691f0b2e"
API_SECRET = "b26698573b80f5e"
AUTH = f"token {API_KEY}:{API_SECRET}"


def request(method, path, payload=None):
    data = None
    headers = {
        "Authorization": AUTH,
        "Content-Type": "application/json",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ERPNextPatch/1.0",
    }
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(BASE_URL + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as res:
            raw = res.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        raise RuntimeError(f"{method} {path} failed: {e.code} {body[:1000]}") from e


def enc(value):
    return urllib.parse.quote(value, safe="")


def get_doc(doctype, name):
    return request("GET", f"/api/resource/{enc(doctype)}/{enc(name)}")["data"]


def put_doc(doctype, name, payload):
    return request("PUT", f"/api/resource/{enc(doctype)}/{enc(name)}", payload)["data"]


def post_doc(doctype, payload):
    return request("POST", f"/api/resource/{enc(doctype)}", payload)["data"]


def exists(doctype, name):
    try:
        get_doc(doctype, name)
        return True
    except RuntimeError as e:
        if " 404 " in str(e):
            return False
        raise


def upsert_custom_field(doc):
    name = doc["name"]
    if exists("Custom Field", name):
        body = {k: v for k, v in doc.items() if k not in ("doctype", "name")}
        put_doc("Custom Field", name, body)
        print(f"Updated Custom Field: {name}")
    else:
        post_doc("Custom Field", doc)
        print(f"Created Custom Field: {name}")


def upsert_server_script(doc):
    name = doc["name"]
    if exists("Server Script", name):
        body = {k: v for k, v in doc.items() if k not in ("doctype", "name")}
        put_doc("Server Script", name, body)
        print(f"Updated Server Script: {name}")
    else:
        post_doc("Server Script", doc)
        print(f"Created Server Script: {name}")


def main():
    print(f"Applying Account Details workflow patch to TEST only: {BASE_URL}")

    task_kind = get_doc("Custom Field", "Task-task_kind")
    current = [x.strip() for x in (task_kind.get("options") or "").splitlines() if x.strip()]
    current = [x for x in current if x not in ("Account details", "Account Details: Entry", "Account Details: Processing")]
    new_options = []
    inserted = False
    for option in current:
        new_options.append(option)
        if option == "Write-off Approval":
            new_options.append("Account Details: Entry")
            new_options.append("Account Details: Processing")
            inserted = True
    if not inserted:
        new_options.append("Account Details: Entry")
        new_options.append("Account Details: Processing")
    put_doc("Custom Field", "Task-task_kind", {"options": "\n".join(new_options)})
    print("Updated Task Kind options")

    upsert_custom_field({
        "doctype": "Custom Field",
        "name": "Task-custom_account_details_entry_task",
        "dt": "Task",
        "fieldname": "custom_account_details_entry_task",
        "label": "Account Details Entry Task",
        "fieldtype": "Link",
        "options": "Task",
        "insert_after": "custom_next_task_assign_to",
        "hidden": 1,
        "read_only": 1,
    })

    default_script = get_doc("Server Script", "Task-Account Details Default Assignment")
    default_text = default_script.get("script") or ""
    default_text = default_text.replace('doc.get("task_kind") == "Account details"', 'doc.get("task_kind") == "Account Details: Entry"')
    default_text = default_text.replace('doc.subject = "Account details"', 'doc.subject = "Account Details: Entry"')
    put_doc("Server Script", "Task-Account Details Default Assignment", {"script": default_text})
    print("Updated Account Details default assignment script")

    policy = get_doc("Server Script", "Task-before-save-policy")
    policy_text = policy.get("script") or ""
    old_policy = '"Account details": ["Ops - Accounting", "Ops - Finance", "Ops - Directors"],'
    new_policy = '"Account Details: Entry": ["Ops - Accounting", "Ops - Finance", "Ops - Directors"],\n    "Account Details: Processing": ["Ops - Accounting", "Ops - Finance", "Ops - Directors"],'
    policy_text = policy_text.replace(old_policy, new_policy)
    policy_text = policy_text.replace('"Account details"', '"Account Details: Entry"')
    put_doc("Server Script", "Task-before-save-policy", {"script": policy_text})
    print("Updated Task policy script")

    processing_script = '''if doc.get("task_kind") == "Account Details: Entry":
    before = doc.get_doc_before_save()
    before_status = None
    if before:
        before_status = before.status

    if doc.status == "Completed" and before_status != "Completed":
        existing = frappe.db.exists("Task", {"custom_account_details_entry_task": doc.name})
        if not existing:
            assignee = doc.get("custom_next_task_assign_to")
            if not assignee:
                assignee = "accounting.team@example.com"

            new_task = frappe.new_doc("Task")
            new_task.subject = doc.subject or "Account Details: Processing"
            new_task.task_kind = "Account Details: Processing"
            new_task.task_access_policy = "Account Details: Processing"
            new_task.status = "Open"
            new_task.description = doc.description
            new_task.priority = doc.priority
            new_task.customer = doc.customer
            new_task.exp_start_date = doc.exp_start_date
            new_task.exp_end_date = doc.exp_end_date
            new_task.expected_time = doc.expected_time
            new_task.custom_assigned_to = assignee
            new_task.custom_account_details_entry_task = doc.name

            if doc.get("custom_account_photos"):
                for row in doc.get("custom_account_photos"):
                    new_task.append("custom_account_photos", row.as_dict())

            new_task.flags.ignore_permissions = True
            new_task.insert()

            frappe.db.set_value("Task", new_task.name, "_assign", json.dumps([assignee]))
            todo = frappe.new_doc("ToDo")
            todo.status = "Open"
            todo.allocated_to = assignee
            todo.reference_type = "Task"
            todo.reference_name = new_task.name
            todo.description = new_task.subject or new_task.name
            todo.assigned_by = frappe.session.user
            todo.flags.ignore_permissions = True
            todo.insert()

            files = frappe.get_all("File", filters={"attached_to_doctype": "Task", "attached_to_name": doc.name}, fields=["file_url", "file_name", "is_private", "attached_to_field"])
            for f in files:
                nf = frappe.new_doc("File")
                nf.file_url = f.file_url
                nf.file_name = f.file_name
                nf.is_private = f.is_private
                nf.attached_to_doctype = "Task"
                nf.attached_to_name = new_task.name
                nf.attached_to_field = f.attached_to_field
                nf.flags.ignore_permissions = True
                nf.insert()
'''

    upsert_server_script({
        "doctype": "Server Script",
        "name": "Task-after-save-account-details-processing",
        "script_type": "DocType Event",
        "reference_doctype": "Task",
        "doctype_event": "After Save",
        "disabled": 0,
        "script": processing_script,
    })

    print("Patch complete on TEST. No Task deletion was performed.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
