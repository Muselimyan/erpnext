import json
import sys
import time
import urllib.parse
import urllib.request
import urllib.error

BASE_URL = "https://test.erpnext.am"
AUTH = "token af78cbd691f0b2e:b26698573b80f5e"
HEADERS = {
    "Authorization": AUTH,
    "Content-Type": "application/json",
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ERPNextDelete/1.0",
}
DISPATCH_TASK_FIELDS = [
    "order_entry_task",
    "discount_approval_task",
    "pack_task",
    "delivery_task",
    "return_waiting_task",
    "return_pickup_task",
    "returns_inspection_task",
    "restock_task",
    "invoice_task",
]


def enc(value):
    return urllib.parse.quote(value, safe="")


def request(method, path, payload=None, timeout=60):
    data = None
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(BASE_URL + path, data=data, headers=HEADERS, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as res:
            raw = res.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        raise RuntimeError(f"{method} {path} failed: {e.code} {body[:800]}") from e


def list_docs(doctype, fields, filters=None):
    path = f"/api/resource/{enc(doctype)}?fields={enc(json.dumps(fields))}&limit_page_length=10000"
    if filters:
        path += "&filters=" + enc(json.dumps(filters))
    return request("GET", path, timeout=60).get("data", [])


def count(doctype, filters=None):
    params = urllib.parse.urlencode({"doctype": doctype, "filters": json.dumps(filters or {})})
    return request("GET", f"/api/method/frappe.client.get_count?{params}", timeout=60).get("message")


def set_value(doctype, name, fieldname, value):
    payload = {"doctype": doctype, "name": name, "fieldname": fieldname, "value": value}
    return request("POST", "/api/method/frappe.client.set_value", payload, timeout=60)


def clear_links():
    cleared = 0
    fields = ["name"] + DISPATCH_TASK_FIELDS
    for row in list_docs("Dispatch Case", fields):
        for field in DISPATCH_TASK_FIELDS:
            if row.get(field):
                set_value("Dispatch Case", row["name"], field, "")
                cleared += 1
    for row in list_docs("Task", ["name", "parent_task"], [["parent_task", "is", "set"]]):
        set_value("Task", row["name"], "parent_task", "")
        cleared += 1
    print(f"Cleared Task links: {cleared}")


def delete_docs(doctype, names):
    ok = 0
    fail = 0
    for i, name in enumerate(names, 1):
        try:
            request("DELETE", f"/api/resource/{enc(doctype)}/{enc(name)}", timeout=60)
            ok += 1
        except Exception as exc:
            fail += 1
            print(f"FAILED {doctype} {name}: {exc}")
        if i % 25 == 0:
            print(f"{doctype}: deleted {ok}, failed {fail}, processed {i}/{len(names)}")
            time.sleep(0.5)
    print(f"{doctype}: deleted {ok}, failed {fail}, total {len(names)}")


def main():
    print(f"Clearing Task links and deleting remaining Tasks on TEST only: {BASE_URL}")
    print("Before:")
    print("Task:", count("Task", {}))
    print("Comment_Task:", count("Comment", {"reference_doctype": "Task"}))
    clear_links()
    comments = [r["name"] for r in list_docs("Comment", ["name"], [["reference_doctype", "=", "Task"]])]
    tasks = [r["name"] for r in list_docs("Task", ["name"])]
    delete_docs("Comment", comments)
    delete_docs("Task", tasks)
    print("After:")
    print("Task:", count("Task", {}))
    print("ToDo_Task:", count("ToDo", {"reference_type": "Task"}))
    print("Comment_Task:", count("Comment", {"reference_doctype": "Task"}))
    print("File_Task:", count("File", {"attached_to_doctype": "Task"}))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
