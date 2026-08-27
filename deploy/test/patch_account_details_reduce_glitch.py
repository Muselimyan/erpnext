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
    print(f"Reducing Account Details UI flicker on TEST only: {BASE_URL}")
    doc = request("GET", f"/api/resource/{enc('Client Script')}/{enc(SCRIPT_NAME)}")["data"]
    script = doc.get("script") or ""

    old_refresh = '''    refresh(frm) {
        task_account_details_ui_cleanup(frm);
        setTimeout(function() { task_account_details_ui_cleanup(frm); }, 200);
        setTimeout(function() { task_account_details_ui_cleanup(frm); }, 800);
        setTimeout(function() { task_account_details_ui_cleanup(frm); }, 1600);
        setTimeout(function() { task_account_details_ui_cleanup(frm); }, 3000);
    },'''
    new_refresh = '''    refresh(frm) {
        task_account_details_ui_cleanup(frm);
        clearTimeout(frm._account_details_cleanup_timer);
        frm._account_details_cleanup_timer = setTimeout(function() { task_account_details_ui_cleanup(frm); }, 250);
    },'''
    if old_refresh in script:
        script = script.replace(old_refresh, new_refresh, 1)
    elif new_refresh not in script:
        raise RuntimeError("Expected repeated refresh cleanup block not found")

    script = script.replace('''                task_account_details_render_photo_preview(frm, photosControl);
                setTimeout(function() { task_account_details_render_photo_preview(frm, photosControl); }, 1000);
                frm.reload_doc();''', '''                task_account_details_render_photo_preview(frm, photosControl);
                frm.reload_doc();''')

    script = script.replace('''    task_account_details_render_photo_preview(frm, photosControl);
    setTimeout(function() { task_account_details_render_photo_preview(frm, photosControl); }, 800);
    setTimeout(function() { task_account_details_render_photo_preview(frm, photosControl); }, 1800);''', '''    task_account_details_render_photo_preview(frm, photosControl);''')

    request("PUT", f"/api/resource/{enc('Client Script')}/{enc(SCRIPT_NAME)}", {"script": script, "enabled": 1})
    print("Updated Client Script: Task-Account Details UI Cleanup")
    print("Patch complete on TEST. Repeated cleanup/photo rerenders were reduced.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
