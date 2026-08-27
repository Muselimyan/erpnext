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
SCRIPT_NAME = "Task-after-save-account-details-processing"


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


def main():
    print(f"Patching Processing image inheritance on TEST only: {BASE_URL}")
    doc = request("GET", f"/api/resource/{enc('Server Script')}/{enc(SCRIPT_NAME)}")["data"]
    script = doc.get("script") or ""

    old = '''            files = frappe.get_all("File", filters={"attached_to_doctype": "Task", "attached_to_name": doc.name}, fields=["file_url", "file_name", "is_private", "attached_to_field"])
            for f in files:
                nf = frappe.new_doc("File")
                nf.file_url = f.file_url
                nf.file_name = f.file_name
                nf.is_private = f.is_private
                nf.attached_to_doctype = "Task"
                nf.attached_to_name = new_task.name
                nf.attached_to_field = f.attached_to_field
                nf.flags.ignore_permissions = True
                nf.insert()'''
    new = '''            files = frappe.get_all("File", filters={"attached_to_doctype": "Task", "attached_to_name": doc.name}, fields=["file_url", "file_name", "is_private", "attached_to_field", "folder"])
            for f in files:
                if not f.file_url:
                    continue
                duplicate = frappe.db.exists("File", {
                    "attached_to_doctype": "Task",
                    "attached_to_name": new_task.name,
                    "file_url": f.file_url
                })
                if duplicate:
                    continue
                nf = frappe.new_doc("File")
                nf.file_url = f.file_url
                nf.file_name = f.file_name
                nf.is_private = f.is_private
                nf.folder = f.folder or "Home/Attachments"
                nf.attached_to_doctype = "Task"
                nf.attached_to_name = new_task.name
                nf.attached_to_field = f.attached_to_field
                nf.flags.ignore_permissions = True
                nf.insert()'''
    if old not in script and new not in script:
        raise RuntimeError("Expected file copy block not found")
    script = script.replace(old, new)

    request("PUT", f"/api/resource/{enc('Server Script')}/{enc(SCRIPT_NAME)}", {"script": script, "disabled": 0})
    print("Updated Server Script: Task-after-save-account-details-processing")
    print("Patch complete on TEST. Processing tasks will inherit Entry attached images/files.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
