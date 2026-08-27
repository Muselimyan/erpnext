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
    print(f"Patching Account Details Processing UI cleanup on TEST only: {BASE_URL}")
    doc = get_script()
    script = doc.get("script") or ""

    script = script.replace(
        'var is_account_details = taskKind === "account details" || taskKind === "account details: entry";',
        'var is_account_details = taskKind === "account details" || taskKind === "account details: entry" || taskKind === "account details: processing";'
    )
    script = script.replace(
        'if (taskKind !== "account details" && taskKind !== "account details: entry") return;',
        'if (taskKind !== "account details" && taskKind !== "account details: entry" && taskKind !== "account details: processing") return;'
    )

    put_script(script)
    print("Updated Client Script: Task-Account Details UI Cleanup")
    print("Patch complete on TEST. Only Processing was added to existing cleanup logic.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
