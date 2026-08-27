import json
import urllib.parse
import urllib.request

BASE_URL = "https://test.erpnext.am"
AUTH = "token af78cbd691f0b2e:b26698573b80f5e"
HEADERS = {
    "Authorization": AUTH,
    "Content-Type": "application/json",
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ERPNextVerify/1.0",
}


def request(path):
    req = urllib.request.Request(BASE_URL + path, headers=HEADERS, method="GET")
    with urllib.request.urlopen(req, timeout=60) as res:
        return json.loads(res.read().decode("utf-8"))


def count(doctype, filters=None):
    params = urllib.parse.urlencode({"doctype": doctype, "filters": json.dumps(filters or {})})
    return request(f"/api/method/frappe.client.get_count?{params}").get("message")


for label, dt, filters in [
    ("Task", "Task", {}),
    ("ToDo_Task", "ToDo", {"reference_type": "Task"}),
    ("Comment_Task", "Comment", {"reference_doctype": "Task"}),
    ("File_Task", "File", {"attached_to_doctype": "Task"}),
]:
    print(f"{label}: {count(dt, filters)}")
