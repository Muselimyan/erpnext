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
    print(f"Patching Account Details image fullscreen viewer on TEST only: {BASE_URL}")
    doc = request("GET", f"/api/resource/{enc('Client Script')}/{enc(SCRIPT_NAME)}")["data"]
    script = doc.get("script") or ""

    old = '''            var dialog = new frappe.ui.Dialog({ title: title, size: 'large' });
            dialog.$body.html('<div style="display:flex;gap:8px;justify-content:center;margin-bottom:10px;"><button class="btn btn-sm btn-default" data-photo-zoom-out="1">-</button><button class="btn btn-sm btn-default" data-photo-zoom-reset="1">Reset</button><button class="btn btn-sm btn-default" data-photo-zoom-in="1">+</button></div><div data-photo-zoom-wrap="1" style="text-align:center;padding:10px;overflow:auto;max-height:75vh;border:1px solid #eef0f2;border-radius:4px;"><img data-photo-zoom-img="1" src="' + url + '" style="max-width:100%;max-height:70vh;object-fit:contain;border-radius:4px;transform:scale(1);transform-origin:center center;transition:transform .12s ease;" /></div>');
            dialog.show();
            var zoom = 1;
            var applyZoom = function() {
                dialog.$body.find('[data-photo-zoom-img]').css('transform', 'scale(' + zoom + ')');
            };
            dialog.$body.find('[data-photo-zoom-in]').on('click', function() { zoom = Math.min(zoom + 0.25, 4); applyZoom(); });
            dialog.$body.find('[data-photo-zoom-out]').on('click', function() { zoom = Math.max(zoom - 0.25, 0.5); applyZoom(); });
            dialog.$body.find('[data-photo-zoom-reset]').on('click', function() { zoom = 1; applyZoom(); });
            dialog.$body.find('[data-photo-zoom-img]').on('wheel', function(ev) {
                ev.preventDefault();
                zoom = ev.originalEvent.deltaY < 0 ? Math.min(zoom + 0.15, 4) : Math.max(zoom - 0.15, 0.5);
                applyZoom();
            });'''
    new = '''            $('#account-details-fullscreen-photo-viewer').remove();
            var overlay = $('<div id="account-details-fullscreen-photo-viewer" style="position:fixed;inset:0;background:rgba(0,0,0,.94);z-index:999999;display:flex;align-items:center;justify-content:center;padding:14px;cursor:zoom-out;"></div>');
            var closeBtn = $('<button type="button" style="position:absolute;top:14px;right:18px;background:#fff;color:#111;border:0;border-radius:50%;width:38px;height:38px;font-size:24px;line-height:34px;cursor:pointer;z-index:2;">×</button>');
            var img = $('<img src="' + url + '" alt="' + title + '" style="max-width:96vw;max-height:92vh;object-fit:contain;border-radius:4px;box-shadow:0 8px 28px rgba(0,0,0,.45);cursor:auto;" />');
            overlay.append(closeBtn).append(img);
            $('body').append(overlay);
            var closeViewer = function() { overlay.remove(); $(document).off('keydown.accountDetailsFullscreenPhoto'); };
            closeBtn.on('click', function(e) { e.preventDefault(); closeViewer(); });
            overlay.on('click', function(e) { if (e.target === overlay[0]) closeViewer(); });
            $(document).on('keydown.accountDetailsFullscreenPhoto', function(e) { if (e.key === 'Escape') closeViewer(); });'''
    if old not in script:
        raise RuntimeError("Expected zoom preview block not found; refresh/patched script may differ")
    script = script.replace(old, new)

    request("PUT", f"/api/resource/{enc('Client Script')}/{enc(SCRIPT_NAME)}", {"script": script, "enabled": 1})
    print("Updated Client Script: Task-Account Details UI Cleanup")
    print("Patch complete on TEST. Image preview now opens fullscreen.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
