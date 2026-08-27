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


def main():
    print(f"Forcing Account Details Subject visible on TEST only: {BASE_URL}")
    doc = request("GET", f"/api/resource/{enc('Client Script')}/{enc(SCRIPT_NAME)}")["data"]
    script = doc.get("script") or ""

    old = '''        var photosControl = wrapper.find('[data-fieldname="custom_account_photos"]').closest('.frappe-control');'''
    new = '''        var subjectControl = wrapper.find('[data-fieldname="subject"]').closest('.frappe-control');
        if (subjectControl.length) {
            subjectControl.show();
            subjectControl.find('.control-label, label').show();
            subjectControl.find('input, textarea').prop('required', false).show();
        }
        var photosControl = wrapper.find('[data-fieldname="custom_account_photos"]').closest('.frappe-control');'''
    if old not in script and new not in script:
        raise RuntimeError("Expected photo control placement line not found")
    script = script.replace(old, new, 1)

    old_insert = '''        if (statusControl.length) {
            photosBoxHost.insertBefore(statusControl);'''
    new_insert = '''        if (subjectControl.length) {
            photosBoxHost.insertAfter(subjectControl);
        } else if (statusControl.length) {
            photosBoxHost.insertBefore(statusControl);'''
    if old_insert in script:
        script = script.replace(old_insert, new_insert, 1)

    request("PUT", f"/api/resource/{enc('Client Script')}/{enc(SCRIPT_NAME)}", {"script": script, "enabled": 1})
    print("Updated Client Script: Task-Account Details UI Cleanup")
    print("Patch complete on TEST. Subject is forced visible for Account Details layout.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
