import json
import urllib.parse
import urllib.request

BASE_URL = "https://test.erpnext.am"
AUTH = "token af78cbd691f0b2e:b26698573b80f5e"
HEADERS = {
    "Authorization": AUTH,
    "Content-Type": "application/json",
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ERPNextInspect/1.0",
}

def enc(value):
    return urllib.parse.quote(value, safe="")

def request(path):
    req = urllib.request.Request(BASE_URL + path, headers=HEADERS, method="GET")
    with urllib.request.urlopen(req, timeout=60) as res:
        return json.loads(res.read().decode("utf-8"))

fields = enc(json.dumps(["name", "reference_doctype", "doctype_event", "disabled", "modified"]))
rows = request(f"/api/resource/{enc('Server Script')}?fields={fields}&limit_page_length=500")["data"]
for row in rows:
    doc = request(f"/api/resource/{enc('Server Script')}/{enc(row['name'])}")["data"]
    script = doc.get("script") or ""
    if doc.get("reference_doctype") == "Task" and any(term in script for term in ["Account details", "Account Details", "task_kind", "task_access_policy"]):
        print("\n=====", doc.get("name"), "|", doc.get("doctype_event"), "| disabled=", doc.get("disabled"), "=====")
        print(script)
