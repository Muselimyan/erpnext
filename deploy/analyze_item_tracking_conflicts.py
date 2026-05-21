import csv
import re
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "1c" / "items.csv"

with SOURCE.open("r", encoding="utf-8-sig", newline="") as f:
    rows = list(csv.DictReader(f))

def text(row):
    return " ".join(str(row.get(k, "")) for k in ["description", "print_name", "reference", "sku", "group", "item_type"]).lower()

def has_1(row):
    return "(1)" in text(row)

def has_screw(row):
    return "screw" in text(row)

def has_set_or_kit(row):
    return re.search(r"\b(set|kit|surgery set|instrument set)\b", text(row)) is not None

def has_instrument(row):
    return re.search(r"\b(instrument|screwdriver|drill|reamer|tool|handle)\b", text(row)) is not None

def is_expiry(row):
    return row.get("item_type") == "Ժամկետով ապրանքներ"

print("TOTAL", len(rows))
for label, fn in [
    ("contains_(1)", has_1),
    ("contains_screw", has_screw),
    ("contains_set_or_kit", has_set_or_kit),
    ("contains_instrument", has_instrument),
    ("expiry_item_type", is_expiry),
]:
    print(label, sum(1 for r in rows if fn(r)))

print("\nGROUPS_WITH_(1)")
for group, count in Counter(r.get("group", "") for r in rows if has_1(r)).most_common(100):
    print(count, group)

print("\nSCREWS_BY_GROUP_AND_ITEM_TYPE")
d = defaultdict(Counter)
for r in rows:
    if has_screw(r):
        d[r.get("group", "")][r.get("item_type", "")] += 1
for group in sorted(d):
    print(group, dict(d[group]))

print("\nSET_KIT_BY_GROUP_AND_ITEM_TYPE")
d = defaultdict(Counter)
for r in rows:
    if has_set_or_kit(r):
        d[r.get("group", "")][r.get("item_type", "")] += 1
for group in sorted(d):
    print(group, dict(d[group]))

print("\nINSTRUMENT_BY_GROUP_AND_ITEM_TYPE")
d = defaultdict(Counter)
for r in rows:
    if has_instrument(r):
        d[r.get("group", "")][r.get("item_type", "")] += 1
for group in sorted(d):
    print(group, dict(d[group]))

print("\nSAMPLE_(1)_ROWS")
for r in [r for r in rows if has_1(r)][:120]:
    print(r.get("code_1c"), r.get("sku"), r.get("group"), r.get("item_type"), r.get("description"))
