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
    print(f"Patching clean per-task photo preview on TEST only: {BASE_URL}")
    doc = request("GET", f"/api/resource/{enc('Client Script')}/{enc(SCRIPT_NAME)}")["data"]
    script = doc.get("script") or ""

    old = '''function task_account_details_render_photos_box(frm, photosControl) {
    if (!photosControl || !photosControl.length) return;
    photosControl.find('.account-details-add-photos-box').remove();'''
    new = '''function task_account_details_render_photos_box(frm, photosControl) {
    if (!photosControl || !photosControl.length) return;
    photosControl.find('.account-details-add-photos-box').remove();
    photosControl.find('.account-details-photo-gallery').remove();
    photosControl.find('[data-account-details-new-doc-photo-cleanup]').remove();
    $('#account-details-fullscreen-photo-viewer').remove();'''
    if old not in script and new not in script:
        raise RuntimeError("Expected render photos box header not found")
    script = script.replace(old, new)

    old_new_doc = '''    if (frm.is_new()) {
        photosControl.append('<div data-account-details-new-doc-photo-cleanup="accountDetailsNewDocPhotoCleanup" style="font-size:11px;color:#8d99a6;margin-top:8px;">Photos will be available after saving this task.</div>');
        return;
    }'''
    new_new_doc = '''    if (frm.is_new()) {
        photosControl.find('.account-details-photo-gallery').remove();
        photosControl.find('[data-account-details-new-doc-photo-cleanup]').remove();
        return;
    }'''
    if old_new_doc in script:
        script = script.replace(old_new_doc, new_new_doc)

    old_filters = '''            filters: {
                attached_to_doctype: 'Task',
                attached_to_name: frm.doc.name,
                is_private: ['in', [0, 1]]
            },'''
    new_filters = '''            filters: {
                attached_to_doctype: 'Task',
                attached_to_name: frm.doc.name,
                is_private: ['in', [0, 1]]
            },'''
    if old_filters not in script:
        raise RuntimeError("Expected current-task File filter not found")
    script = script.replace(old_filters, new_filters)

    request("PUT", f"/api/resource/{enc('Client Script')}/{enc(SCRIPT_NAME)}", {"script": script, "enabled": 1})
    print("Updated Client Script: Task-Account Details UI Cleanup")
    print("Patch complete on TEST. Photo previews are now clean per task; saved attachments are preserved.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
