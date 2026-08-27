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


def patch_default_assignment():
    name = "Task-Account Details Default Assignment"
    doc = get_doc("Server Script", name)
    script = doc.get("script") or ""
    line = 'if doc.get("task_kind") == "Account Details: Entry":'
    insert = '''if doc.get("task_kind") == "Account Details: Entry":
    if doc.get("custom_account_details_subject"):
        doc.subject = doc.get("custom_account_details_subject")'''
    if 'doc.get("custom_account_details_subject")' not in script:
        if line not in script:
            raise RuntimeError("Could not find Entry condition in default assignment script")
        script = script.replace(line, insert, 1)
    put_doc("Server Script", name, {"script": script, "disabled": 0})
    print(f"Updated Server Script: {name}")


def patch_processing_script():
    name = "Task-after-save-account-details-processing"
    doc = get_doc("Server Script", name)
    script = doc.get("script") or ""
    replacements = [
        ('new_task.subject = doc.subject or "Account Details: Processing"', 'new_task.subject = doc.get("custom_account_details_subject") or doc.subject or "Account Details: Processing"\n            new_task.custom_account_details_subject = doc.get("custom_account_details_subject") or doc.subject'),
        ('new_task.subject = "Account Details: Processing"', 'new_task.subject = doc.get("custom_account_details_subject") or doc.subject or "Account Details: Processing"\n            new_task.custom_account_details_subject = doc.get("custom_account_details_subject") or doc.subject'),
    ]
    changed = False
    for old, new in replacements:
        if old in script:
            script = script.replace(old, new, 1)
            changed = True
            break
    if not changed and 'new_task.custom_account_details_subject = doc.get("custom_account_details_subject") or doc.subject' not in script:
        raise RuntimeError("Expected Processing subject assignment line not found")
    put_doc("Server Script", name, {"script": script, "disabled": 0})
    print(f"Updated Server Script: {name}")


def main():
    print(f"Completing visible Subject server-side sync on TEST only: {BASE_URL}")
    patch_default_assignment()
    patch_processing_script()
    print("Patch complete on TEST. Subject box is synced and copied from Entry to Processing.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
