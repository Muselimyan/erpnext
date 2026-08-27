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
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ERPNextDelete/1.0",
}
SCRIPT_NAME = "test_delete_remaining_task_comments"

SERVER_SCRIPT = r'''
def c(dt, filters=None):
    return frappe.db.count(dt, filters or {})

before = {
    "Task": c("Task"),
    "ToDo_Task": c("ToDo", {"reference_type": "Task"}),
    "Comment_Task": c("Comment", {"reference_doctype": "Task"}),
    "File_Task": c("File", {"attached_to_doctype": "Task"}),
}

deleted_comments = 0
for name in frappe.get_all("Comment", filters={"reference_doctype": "Task"}, pluck="name", limit_page_length=10000):
    try:
        frappe.delete_doc("Comment", name, ignore_permissions=True, force=True, ignore_missing=True)
        deleted_comments += 1
    except Exception:
        pass
frappe.db.commit()

after = {
    "Task": c("Task"),
    "ToDo_Task": c("ToDo", {"reference_type": "Task"}),
    "Comment_Task": c("Comment", {"reference_doctype": "Task"}),
    "File_Task": c("File", {"attached_to_doctype": "Task"}),
}

frappe.response["message"] = {"before": before, "deleted_comments": deleted_comments, "after": after}
'''


def enc(value):
    return urllib.parse.quote(value, safe="")


def request(method, path, payload=None, timeout=120):
    data = None
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(BASE_URL + path, data=data, headers=HEADERS, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as res:
            raw = res.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        raise RuntimeError(f"{method} {path} failed: {e.code} {body[:1500]}") from e


def delete_script_if_exists():
    try:
        request("DELETE", f"/api/resource/{enc('Server Script')}/{enc(SCRIPT_NAME)}", timeout=60)
    except Exception:
        pass


def main():
    print(f"Deleting remaining Task comments on TEST only: {BASE_URL}")
    delete_script_if_exists()
    payload = {
        "doctype": "Server Script",
        "name": SCRIPT_NAME,
        "script_type": "API",
        "api_method": SCRIPT_NAME,
        "disabled": 0,
        "script": SERVER_SCRIPT,
    }
    request("POST", f"/api/resource/{enc('Server Script')}", payload, timeout=60)
    try:
        result = request("POST", f"/api/method/{enc(SCRIPT_NAME)}", timeout=300)
        print(json.dumps(result.get("message"), indent=2))
    finally:
        delete_script_if_exists()
        print("Temporary Server Script deleted")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
