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
    print(f"Patching Account Details image preview on TEST only: {BASE_URL}")
    doc = request("GET", f"/api/resource/{enc('Client Script')}/{enc(SCRIPT_NAME)}")["data"]
    script = doc.get("script") or ""

    old = '''html += '<a href="' + url + '" target="_blank" style="display:block;text-decoration:none;line-height:0;">';
            html += '<img src="' + url + '" title="' + title + '" style="width:90px;max-height:140px;object-fit:cover;border:1px solid #d1d8dd;border-radius:4px;background:#f8f9fa;" />';
            html += '</a>';'''
    new = '''html += '<a href="#" data-account-details-preview-url="' + encodeURIComponent(url) + '" data-account-details-preview-title="' + encodeURIComponent(title) + '" style="display:block;text-decoration:none;line-height:0;">';
            html += '<img src="' + url + '" title="' + title + '" style="width:90px;max-height:140px;object-fit:cover;border:1px solid #d1d8dd;border-radius:4px;background:#f8f9fa;cursor:pointer;" />';
            html += '</a>';'''
    if old not in script and new not in script:
        raise RuntimeError("Expected photo gallery anchor block not found")
    script = script.replace(old, new)

    handler_marker = "photosControl.off('click.accountDetailsPreview')"
    handler = r'''
        photosControl.off('click.accountDetailsPreview').on('click.accountDetailsPreview', '[data-account-details-preview-url]', function(e) {
            e.preventDefault();
            var url = decodeURIComponent($(this).attr('data-account-details-preview-url') || '');
            var title = decodeURIComponent($(this).attr('data-account-details-preview-title') || 'Photo');
            if (!url) return;
            var dialog = new frappe.ui.Dialog({ title: title, size: 'large' });
            dialog.$body.html('<div style="text-align:center;padding:10px;"><img src="' + url + '" style="max-width:100%;max-height:75vh;object-fit:contain;border-radius:4px;" /></div>');
            dialog.show();
        });
'''
    insert_after = "photosControl.append(html);"
    if handler_marker not in script:
        if insert_after not in script:
            raise RuntimeError("Expected photo gallery append line not found")
        script = script.replace(insert_after, insert_after + handler, 1)

    request("PUT", f"/api/resource/{enc('Client Script')}/{enc(SCRIPT_NAME)}", {"script": script, "enabled": 1})
    print("Updated Client Script: Task-Account Details UI Cleanup")
    print("Patch complete on TEST. Image clicks now open preview dialog.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
