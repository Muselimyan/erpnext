import csv
import re
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "1c" / "items.csv"
OUT_DETAIL = ROOT / "deploy" / "item-tracking-review-v3.csv"
OUT_GROUPS = ROOT / "deploy" / "item-tracking-group-summary-v3.csv"

EXPIRY_TYPE = "Ժամկետով ապրանքներ"

NON_STERILE_KEYWORDS = [
    "set", "sets", "kit", "instrument", "instruments", "tool", "tools", "screwdriver", "handle", "drill", "reamer",
]
REUSABLE_INSTRUMENT_PATTERNS = [
    "instrument set",
    "instruments for",
    "surgery set",
    "surgical instrument",
]
PLATE_KEYWORDS = ["plate", "plates", "lcp"]
NAIL_KEYWORDS = ["nail", "nails", "pfna", "ten", "ttc", "i.n.", "intr. nail", "intramedullary"]
STERILE_SCREW_BRANDS = ["chunli", "permedica", "just"]
STERILE_PRODUCT_KEYWORDS = [
    "albomed", "cement", "conmed", "gel", "injection", "prosthesis", "stem", "head",
    "cup", "liner", "insert", "shell", "radius", "hip", "knee", "shoulder", "femoral",
    "viscophi", "sophysa", "teknimed",
]
CONFIRMED_STERILE_PATTERNS = [
    "bpb",
    "kyphoplasty",
    "vertebroplastic",
    "sophysa",
    "pressio",
    "monitoring kit",
    "drainage system",
    "catheter",
    "valve",
    "reservoir",
    "genesys matryx",
    "bioscrew",
    "interference screw",
]


def norm(value):
    return (value or "").strip()


def combined_text(row):
    fields = ["description", "print_name", "reference", "sku", "group", "item_type"]
    return " ".join(norm(row.get(field)) for field in fields).lower()


def has_word(text, words):
    return any(re.search(rf"(^|[^a-z0-9]){re.escape(word)}([^a-z0-9]|$)", text) for word in words)


def classify(row):
    text = combined_text(row)
    code_1c = norm(row.get("code_1c"))
    description = norm(row.get("description"))
    group = norm(row.get("group"))
    sku = norm(row.get("sku"))
    item_type = norm(row.get("item_type"))
    flags = []

    if not code_1c and not sku and not description and not group:
        return "SKIP", "LOW", "Blank row without item identity; ignore", "BLANK_ROW"

    is_expiry_type = item_type == EXPIRY_TYPE
    is_instruments_group = group.lower() == "instruments"
    is_non_sterile_tooling = has_word(text, NON_STERILE_KEYWORDS)
    is_reusable_instrument = has_word(text, REUSABLE_INSTRUMENT_PATTERNS)
    is_plate = has_word(text, PLATE_KEYWORDS)
    is_nail = has_word(text, NAIL_KEYWORDS)
    is_screw = "screw" in text
    is_sterile_screw = is_screw and any(brand in text for brand in STERILE_SCREW_BRANDS)
    is_sterile_product = has_word(text, STERILE_PRODUCT_KEYWORDS)
    is_confirmed_sterile = has_word(text, CONFIRMED_STERILE_PATTERNS)

    if not sku:
        flags.append("NO_SKU_REF")

    if is_instruments_group:
        flags.append("INSTRUMENTS_GROUP")
        return "REF_ONLY", "LOW", "Instruments group is reusable/non-sterile REF-only", ";".join(flags)

    if is_confirmed_sterile:
        flags.append("CONFIRMED_STERILE")
        return "BATCH_EXPIRY", "LOW", "User confirmed this product/category is sterile and requires REF + LOT + Expiry", ";".join(flags)

    if is_reusable_instrument:
        flags.append("REUSABLE_INSTRUMENT")
        return "REF_ONLY", "LOW", "Reusable instrument/set is non-sterile REF-only", ";".join(flags)

    if is_non_sterile_tooling:
        flags.append("NON_STERILE_TOOLING")
        if is_expiry_type or is_sterile_product:
            return "REF_ONLY", "HIGH", "Set/kit/instrument/tool is non-sterile; verify because item also looks expiry/sterile", ";".join(flags)
        return "REF_ONLY", "LOW", "Set/kit/instrument/tool is non-sterile", ";".join(flags)

    if is_plate:
        flags.append("PLATE")
        if is_expiry_type:
            return "REF_ONLY", "HIGH", "All plates are non-sterile REF-only; verify because 1C item_type says expiry", ";".join(flags)
        return "REF_ONLY", "LOW", "All plates are non-sterile REF-only", ";".join(flags)

    if is_nail:
        flags.append("NAIL")
        if is_expiry_type:
            return "REF_ONLY", "HIGH", "All nails are non-sterile REF-only; verify because 1C item_type says expiry", ";".join(flags)
        return "REF_ONLY", "LOW", "All nails are non-sterile REF-only", ";".join(flags)

    if is_screw:
        flags.append("SCREW")
        if is_sterile_screw:
            flags.append("STERILE_SCREW_BRAND")
            return "BATCH_EXPIRY", "LOW", "Chunli/Permedica/Just screw requires expiry", ";".join(flags)
        if is_expiry_type:
            return "REF_ONLY", "HIGH", "Usual screws are non-sterile REF-only; verify because 1C item_type says expiry", ";".join(flags)
        return "REF_ONLY", "LOW", "Usual screw is non-sterile REF-only", ";".join(flags)

    if is_expiry_type:
        flags.append("EXPIRY_ITEM_TYPE")
        return "BATCH_EXPIRY", "MEDIUM", "1C item_type says expiry-controlled and no non-sterile override matched", ";".join(flags)

    if is_sterile_product:
        flags.append("STERILE_PRODUCT_KEYWORD")
        return "BATCH_EXPIRY", "MEDIUM", "Looks like sterile prosthesis/component/medical product", ";".join(flags)

    if not sku:
        return "MANUAL_REVIEW", "HIGH", "No SKU/REF; confirm item identity/barcode mapping", ";".join(flags)

    return "REF_ONLY", "MEDIUM", "No sterile indicators matched", ";".join(flags)


def main():
    rows = []
    with SOURCE.open("r", encoding="utf-8-sig", newline="") as source_file:
        for row in csv.DictReader(source_file):
            tracking, risk, reason, flags = classify(row)
            if tracking == "SKIP":
                continue
            rows.append({
                "code_1c": norm(row.get("code_1c")),
                "sku_ref": norm(row.get("sku")),
                "description": norm(row.get("description")),
                "group": norm(row.get("group")),
                "item_type": norm(row.get("item_type")),
                "uom": norm(row.get("uom")),
                "suggested_tracking": tracking,
                "risk_level": risk,
                "needs_user_review": "YES" if risk == "HIGH" or tracking == "MANUAL_REVIEW" else "NO",
                "reason": reason,
                "flags": flags,
                "approved_tracking": "",
                "user_note": "",
            })

    with OUT_DETAIL.open("w", encoding="utf-8-sig", newline="") as output_file:
        writer = csv.DictWriter(output_file, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    group_counts = defaultdict(Counter)
    for row in rows:
        group_counts[row["group"]][row["suggested_tracking"]] += 1
        group_counts[row["group"]][row["risk_level"]] += 1
        group_counts[row["group"]]["TOTAL"] += 1

    summary_rows = []
    for group, counts in sorted(group_counts.items()):
        summary_rows.append({
            "group": group,
            "total_items": counts["TOTAL"],
            "suggest_batch_expiry": counts["BATCH_EXPIRY"],
            "suggest_ref_only": counts["REF_ONLY"],
            "manual_review": counts["MANUAL_REVIEW"],
            "high_risk": counts["HIGH"],
            "medium_risk": counts["MEDIUM"],
            "low_risk": counts["LOW"],
            "group_decision": "",
            "note": "",
        })

    with OUT_GROUPS.open("w", encoding="utf-8-sig", newline="") as output_file:
        writer = csv.DictWriter(output_file, fieldnames=list(summary_rows[0].keys()))
        writer.writeheader()
        writer.writerows(summary_rows)

    tracking_counts = Counter(row["suggested_tracking"] for row in rows)
    risk_counts = Counter(row["risk_level"] for row in rows)
    print("V3 item tracking review generated")
    print(f"Source rows: {len(rows)}")
    print(f"BATCH_EXPIRY: {tracking_counts['BATCH_EXPIRY']}")
    print(f"REF_ONLY: {tracking_counts['REF_ONLY']}")
    print(f"MANUAL_REVIEW: {tracking_counts['MANUAL_REVIEW']}")
    print(f"HIGH risk: {risk_counts['HIGH']}")
    print(f"MEDIUM risk: {risk_counts['MEDIUM']}")
    print(f"LOW risk: {risk_counts['LOW']}")
    print(f"Detail: {OUT_DETAIL}")
    print(f"Group summary: {OUT_GROUPS}")


if __name__ == "__main__":
    main()
