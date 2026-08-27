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


def get_script(name):
    return request("GET", f"/api/resource/{enc('Client Script')}/{enc(name)}")["data"]


def put_script(name, script):
    return request("PUT", f"/api/resource/{enc('Client Script')}/{enc(name)}", {"script": script, "enabled": 1})["data"]


def patch_account_details_ui_cleanup():
    name = "Task-Account Details UI Cleanup"
    doc = get_script(name)
    script = doc.get("script") or ""
    old = '''function task_account_details_add_new_accept_button(frm) {
    if (!frm || !frm.is_new || !frm.is_new()) return;
    if (["account details", "account details: entry"].indexOf(String(frm.doc.task_kind || '').trim().toLowerCase()) < 0) return;
    if (frm.page && frm.page.clear_inner_toolbar) {
        frm.page.clear_inner_toolbar();
    }
    frm.add_custom_button(__("Accept / Start Task"), function() {
        task_account_details_prepare_subject(frm);
        frm.save().then(function() {
            frappe.call({
                method: "dispatch_task_accept",
                args: { task_name: frm.doc.name },
                freeze: true,
                freeze_message: __("Accepting task..."),
                callback: function() {
                    frm.reload_doc();
                }
            });
        });
    }).addClass("btn-primary");
}
'''
    new = '''function task_account_details_add_new_accept_button(frm) {
    if (!frm || !frm.is_new || !frm.is_new()) return;
    if (["account details", "account details: entry"].indexOf(String(frm.doc.task_kind || '').trim().toLowerCase()) < 0) return;
    if (frm.page && frm.page.clear_inner_toolbar) {
        frm.page.clear_inner_toolbar();
    }
    frm.add_custom_button(__("Accept / Start Task"), function() {
        task_account_details_prepare_subject(frm);
        frm.save().then(function(saved_doc) {
            var realName = (saved_doc && saved_doc.name) || (frm.doc && frm.doc.name) || "";
            if (!realName || realName.indexOf("new-") === 0) {
                frappe.show_alert({message: __("Task saved. Please click Accept / Start Task again."), indicator: "orange"}, 8);
                frm.reload_doc();
                return;
            }
            frappe.call({
                method: "dispatch_task_accept",
                args: { task_name: realName },
                freeze: true,
                freeze_message: __("Accepting task..."),
                callback: function() {
                    frm.reload_doc();
                }
            });
        });
    }).addClass("btn-primary");
}
'''
    if old not in script:
        raise RuntimeError(f"Expected function block not found in {name}")
    script = script.replace(old, new)
    put_script(name, script)
    print(f"Updated Client Script: {name}")


def patch_task_accept_start():
    name = "Task-Accept Start"
    doc = get_script(name)
    script = doc.get("script") or ""
    script = script.replace(
        'args: { task_name: frm.doc.name },',
        'args: { task_name: ((frm.doc && frm.doc.name && frm.doc.name.indexOf("new-") !== 0) ? frm.doc.name : "") },'
    )
    script = script.replace(
        'frm.save().then(function() { doAcceptM(); });',
        'frm.save().then(function() { if (frm.doc.name && frm.doc.name.indexOf("new-") !== 0) { doAcceptM(); } else { frappe.show_alert({message: __("Task saved. Please click Accept / Start Task again."), indicator: "orange"}, 8); frm.reload_doc(); } });'
    )
    script = script.replace(
        'frm.save().then(function() {\n                        doAccept();\n                    });',
        'frm.save().then(function() {\n                        if (frm.doc.name && frm.doc.name.indexOf("new-") !== 0) { doAccept(); } else { frappe.show_alert({message: __("Task saved. Please click Accept / Start Task again."), indicator: "orange"}, 8); frm.reload_doc(); }\n                    });'
    )
    put_script(name, script)
    print(f"Updated Client Script: {name}")


def main():
    print(f"Patching Account Details Accept button real-name handling on TEST only: {BASE_URL}")
    patch_account_details_ui_cleanup()
    patch_task_accept_start()
    print("Patch complete on TEST. No server scripts, deletion, or prod changes.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
