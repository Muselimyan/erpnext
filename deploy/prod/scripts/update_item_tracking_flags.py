import argparse
import csv
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
DEPLOY = ROOT / "deploy"
CONFIG = DEPLOY / "export.ps1"
REVIEW = DEPLOY / "item-tracking-review-v3.csv"
OUT_REPORT = DEPLOY / "item-tracking-update-dry-run.csv"
OUT_ERRORS = DEPLOY / "item-tracking-update-errors.csv"

TRACKING_FLAGS = {
    "BATCH_EXPIRY": {"has_batch_no": 1, "has_expiry_date": 1, "has_serial_no": 0, "create_new_batch_automatically": 0},
    "REF_ONLY": {"has_batch_no": 0, "has_expiry_date": 0, "has_serial_no": 0, "create_new_batch_automatically": 0},
}

ITEM_FIELDS = [
    "name",
    "item_code",
    "item_name",
    "item_group",
    "custom_1c_code",
    "has_batch_no",
    "has_expiry_date",
    "has_serial_no",
]


def norm(value):
    return str(value or "").strip()


def read_config():
    text = CONFIG.read_text(encoding="utf-8-sig")
    base_url = re.search(r'\$BaseUrl\s*=\s*"([^"\r\n]+)"', text)
    api_key = re.search(r'\$ApiKey\s*=\s*"([^"\r\n]+)"', text)
    api_sec = re.search(r'\$ApiSec\s*=\s*"([^"\r\n]+)"', text)
    if not base_url or not api_key or not api_sec:
        raise RuntimeError(f"Could not read BaseUrl/ApiKey/ApiSec from {CONFIG}")
    return base_url.group(1).rstrip("/"), api_key.group(1), api_sec.group(1)


def api_request(base_url, api_key, api_sec, method, path, body=None, timeout=30):
    data = None
    headers = {
        "Authorization": f"token {api_key}:{api_sec}",
        "Accept": "application/json",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36",
    }
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = Request(f"{base_url}{path}", data=data, headers=headers, method=method)
    try:
        with urlopen(request, timeout=timeout) as response:
            raw = response.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code}: {detail[:1000]}") from exc
    except URLError as exc:
        raise RuntimeError(f"Network error: {exc}") from exc


def fetch_items(base_url, api_key, api_sec):
    items = []
    limit = 500
    start = 0
    fields = json.dumps(ITEM_FIELDS, separators=(",", ":"))
    while True:
        query = urlencode({
            "fields": fields,
            "limit_start": start,
            "limit_page_length": limit,
        })
        result = api_request(base_url, api_key, api_sec, "GET", f"/api/resource/Item?{query}")
        chunk = result.get("data") or []
        items.extend(chunk)
        if len(chunk) < limit:
            break
        start += limit
    return items


def read_review():
    rows = []
    with REVIEW.open("r", encoding="utf-8-sig", newline="") as review_file:
        for row in csv.DictReader(review_file):
            tracking = norm(row.get("suggested_tracking"))
            if tracking not in TRACKING_FLAGS:
                continue
            rows.append(row)
    return rows


def build_item_indexes(items):
    by_item_code = {}
    by_1c_code = defaultdict(list)
    for item in items:
        item_code = norm(item.get("item_code"))
        custom_1c_code = norm(item.get("custom_1c_code"))
        if item_code:
            by_item_code[item_code] = item
        if custom_1c_code:
            by_1c_code[custom_1c_code].append(item)
    return by_item_code, by_1c_code


def find_item(row, by_item_code, by_1c_code):
    sku_ref = norm(row.get("sku_ref"))
    code_1c = norm(row.get("code_1c"))
    candidates = []
    reasons = []
    for key, reason in ((sku_ref, "sku_ref=item_code"), (code_1c, "code_1c=item_code")):
        if key and key in by_item_code:
            candidates.append(by_item_code[key])
            reasons.append(reason)
    if code_1c and code_1c in by_1c_code:
        for item in by_1c_code[code_1c]:
            candidates.append(item)
            reasons.append("code_1c=custom_1c_code")
    unique = {}
    for item in candidates:
        unique[norm(item.get("name"))] = item
    if len(unique) == 1:
        return next(iter(unique.values())), ";".join(sorted(set(reasons))), ""
    if len(unique) > 1:
        return None, "", ";".join(sorted(unique.keys()))
    return None, "", ""


def desired_flags(tracking):
    return TRACKING_FLAGS[tracking]


def current_flags(item):
    return {
        "has_batch_no": int(item.get("has_batch_no") or 0),
        "has_expiry_date": int(item.get("has_expiry_date") or 0),
        "has_serial_no": int(item.get("has_serial_no") or 0),
        "create_new_batch_automatically": 0,
    }


def flags_match(current, desired):
    return all(current.get(key) == value for key, value in desired.items())


def update_item(base_url, api_key, api_sec, item_name, desired):
    path = f"/api/resource/Item/{quote(item_name, safe='')}"
    return api_request(base_url, api_key, api_sec, "PUT", path, desired)


def write_csv(path, rows, fieldnames):
    with path.open("w", encoding="utf-8-sig", newline="") as output_file:
        writer = csv.DictWriter(output_file, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    base_url, api_key, api_sec = read_config()
    review_rows = read_review()
    print(f"Mode: {'APPLY' if args.apply else 'DRY-RUN'}")
    print(f"Review rows: {len(review_rows)}")
    print("Fetching ERPNext Items...")
    items = fetch_items(base_url, api_key, api_sec)
    print(f"ERPNext Items fetched: {len(items)}")

    by_item_code, by_1c_code = build_item_indexes(items)
    report_rows = []
    error_rows = []
    counts = Counter()

    for row in review_rows:
        tracking = norm(row.get("suggested_tracking"))
        desired = desired_flags(tracking)
        item, matched_by, ambiguous_names = find_item(row, by_item_code, by_1c_code)
        base_report = {
            "code_1c": norm(row.get("code_1c")),
            "sku_ref": norm(row.get("sku_ref")),
            "description": norm(row.get("description")),
            "group": norm(row.get("group")),
            "suggested_tracking": tracking,
            "erp_item_name": "",
            "erp_item_code": "",
            "matched_by": matched_by,
            "current_has_batch_no": "",
            "current_has_expiry_date": "",
            "current_has_serial_no": "",
            "current_create_new_batch_automatically": "",
            "desired_has_batch_no": desired["has_batch_no"],
            "desired_has_expiry_date": desired["has_expiry_date"],
            "desired_has_serial_no": desired["has_serial_no"],
            "desired_create_new_batch_automatically": desired["create_new_batch_automatically"],
            "status": "",
            "message": "",
        }
        if ambiguous_names:
            base_report["status"] = "AMBIGUOUS"
            base_report["message"] = ambiguous_names
            report_rows.append(base_report)
            error_rows.append(base_report)
            counts["ambiguous"] += 1
            continue
        if not item:
            base_report["status"] = "MISSING"
            base_report["message"] = "No ERPNext Item matched by sku_ref/code_1c/custom_1c_code"
            report_rows.append(base_report)
            error_rows.append(base_report)
            counts["missing"] += 1
            continue

        current = current_flags(item)
        base_report.update({
            "erp_item_name": norm(item.get("name")),
            "erp_item_code": norm(item.get("item_code")),
            "current_has_batch_no": current["has_batch_no"],
            "current_has_expiry_date": current["has_expiry_date"],
            "current_has_serial_no": current["has_serial_no"],
            "current_create_new_batch_automatically": current["create_new_batch_automatically"],
        })
        if flags_match(current, desired):
            base_report["status"] = "ALREADY_OK"
            counts["already_ok"] += 1
        else:
            base_report["status"] = "WOULD_UPDATE" if not args.apply else "UPDATED"
            counts["would_update" if not args.apply else "updated"] += 1
            if args.apply:
                try:
                    update_item(base_url, api_key, api_sec, norm(item.get("name")), desired)
                except Exception as exc:
                    base_report["status"] = "ERROR"
                    base_report["message"] = str(exc)
                    error_rows.append(base_report)
                    counts["errors"] += 1
        report_rows.append(base_report)

    fields = [
        "code_1c", "sku_ref", "description", "group", "suggested_tracking",
        "erp_item_name", "erp_item_code", "matched_by",
        "current_has_batch_no", "current_has_expiry_date", "current_has_serial_no", "current_create_new_batch_automatically",
        "desired_has_batch_no", "desired_has_expiry_date", "desired_has_serial_no", "desired_create_new_batch_automatically",
        "status", "message",
    ]
    write_csv(OUT_REPORT, report_rows, fields)
    write_csv(OUT_ERRORS, error_rows, fields)

    tracking_counts = Counter(norm(row.get("suggested_tracking")) for row in review_rows)
    print(f"BATCH_EXPIRY review rows: {tracking_counts['BATCH_EXPIRY']}")
    print(f"REF_ONLY review rows: {tracking_counts['REF_ONLY']}")
    print(f"Already OK: {counts['already_ok']}")
    print(f"Would update: {counts['would_update']}")
    print(f"Updated: {counts['updated']}")
    print(f"Missing: {counts['missing']}")
    print(f"Ambiguous: {counts['ambiguous']}")
    print(f"Errors: {counts['errors']}")
    print(f"Report: {OUT_REPORT}")
    print(f"Errors: {OUT_ERRORS}")
    if not args.apply:
        print("No ERPNext changes were made. Re-run with --apply only after approving this dry-run.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
