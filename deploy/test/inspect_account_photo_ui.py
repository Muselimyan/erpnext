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


print("=== Task fields containing photo/image/attach/file/account/warehouse ===")
doc = request(f"/api/resource/{enc('DocType')}/{enc('Task')}")["data"]
for f in doc.get("fields", []):
    text = " ".join(str(f.get(k) or "") for k in ["fieldname", "label", "fieldtype", "options"]).lower()
    if any(word in text for word in ["photo", "image", "attach", "file", "account", "warehouse"]):
        print(f"{f.get('idx')} | {f.get('fieldname')} | {f.get('label')} | {f.get('fieldtype')} | {f.get('options')}")

print("\n=== Task Client Scripts mentioning photos/accept/account ===")
fields = enc(json.dumps(["name", "dt", "enabled", "modified"]))
rows = request(f"/api/resource/{enc('Client Script')}?fields={fields}&limit_page_length=500")["data"]
for row in rows:
    script_doc = request(f"/api/resource/{enc('Client Script')}/{enc(row['name'])}")["data"]
    script = script_doc.get("script") or ""
    low = script.lower()
    if script_doc.get("dt") == "Task" and any(word in low for word in ["photo", "fileuploader", "accept / start", "account details"]):
        print(f"{script_doc.get('name')} | enabled={script_doc.get('enabled')} | modified={script_doc.get('modified')}")
