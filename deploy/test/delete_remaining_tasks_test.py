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


def list_names(doctype, filters=None):
    fields = enc(json.dumps(["name"]))
    filt = enc(json.dumps(filters or []))
    rows = request("GET", f"/api/resource/{enc(doctype)}?fields={fields}&filters={filt}&limit_page_length=10000", timeout=60).get("data", [])
    return [r["name"] for r in rows]


def count(doctype, filters=None):
    params = urllib.parse.urlencode({"doctype": doctype, "filters": json.dumps(filters or {})})
    return request("GET", f"/api/method/frappe.client.get_count?{params}", timeout=60).get("message")


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
    print(f"Deleting remaining Task records on TEST only: {BASE_URL}")
    comments = list_names("Comment", [["reference_doctype", "=", "Task"]])
    tasks = list_names("Task")
    print(f"Comment_Task before: {len(comments)}")
    print(f"Task before: {len(tasks)}")
    delete_docs("Comment", comments)
    delete_docs("Task", tasks)
    print("After counts:")
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
