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


for dt in ["Task", "Dispatch Case"]:
    doc = request(f"/api/resource/{enc('DocType')}/{enc(dt)}")["data"]
    print(f"=== {dt} fields linking to Task ===")
    for f in doc.get("fields", []):
        if f.get("fieldtype") in ("Link", "Dynamic Link") and f.get("options") == "Task":
            print(f"{f.get('fieldname')} | {f.get('label')} | {f.get('fieldtype')} | {f.get('options')}")
