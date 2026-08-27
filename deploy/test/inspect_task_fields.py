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


def request(path):
    req = urllib.request.Request(BASE_URL + path, headers=HEADERS, method="GET")
    with urllib.request.urlopen(req, timeout=60) as res:
        return json.loads(res.read().decode("utf-8"))


def enc(value):
    return urllib.parse.quote(value, safe="")


doc = request(f"/api/resource/{enc('DocType')}/{enc('Task')}")["data"]
for f in doc.get("fields", []):
    text = " ".join(str(f.get(k) or "") for k in ["fieldname", "label", "fieldtype", "options"]).lower()
    if any(word in text for word in ["photo", "image", "attach", "barcode", "scan", "status", "priority"]):
        print(f"{f.get('idx')} | {f.get('fieldname')} | {f.get('label')} | {f.get('fieldtype')} | {f.get('options')}")
