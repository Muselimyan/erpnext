#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
parse_mxl.py  –  Parse 1C MOXCEL (.mxl) item and price exports.

Handles both {16,...} (plain) and {20,...} (formula/ref) cell encodings.
All string values are kept verbatim from the source (no translation).

Public API
----------
    parse_items(path)  -> list of dicts, one per item row
    parse_prices(path) -> dict  { sku: {"retail": float|None} }
"""

import csv
import re
import sys
import json


# ── Column mapping for items.mxl (positional, 0-based within each row) ─────────

ITEM_COL_NAMES = [
    "code_1c",    # pos 0: 1C internal code,  e.g. "00-00002239"
    "description",# pos 1: English/original item name
    "print_name", # pos 2: Наименование для печати
    "sku",        # pos 3: Артикул – manufacturer article / SKU
    "reference",  # pos 4: Reference
    "group",      # pos 5: Группа – brand / item group
    "item_type",  # pos 6: Вид номенклатуры
    "vat_rate",   # pos 7: Ставка НДС: "20%" | "Без НДС"
    "uom",        # pos 8: Единица хранения
    "hs_code",    # pos 9: Код ТНВЭД
]
ITEM_NCOLS = len(ITEM_COL_NAMES)  # 10


# ── Core regex helpers ────────────────────────────────────────────────────────

def _load_flat(path):
    """Read file as UTF-8 (strip BOM) and collapse all newlines to empty."""
    with open(path, encoding="utf-8-sig") as fh:
        return re.sub(r"[\r\n]+", "", fh.read())


# Non-empty cell:
#   {16|20, N, [{"#", UUID, {M}},]  {1,1,{"#","VALUE"},0},COL,
#   group 1 = value,  group 2 = col index
_VAL_RE = re.compile(
    r'\{(?:16|20),\d+,'
    r'(?:\{"#",[^,\{]+,\{\d+\}\},)?'        # optional UUID ref for {20,...}
    r'\{1,1,\{"#","([^"]*)"\}\},0\},(\d+),'
)

# Empty cell:
#   {16|20, N, [{"#", UUID, {M}},]  {1,0},0},COL,
#   group 1 = col index
_EMPTY_RE = re.compile(
    r'\{(?:16|20),\d+,'
    r'(?:\{"#",[^,\{]+,\{\d+\}\},)?'
    r'\{1,0\},0\},(\d+),'
)


def _extract_fields(flat):
    """
    Return [(value, col_index), ...] in document order.
    Empty cells have value = "".
    """
    hits = []
    for m in _VAL_RE.finditer(flat):
        hits.append((m.start(), m.group(1), int(m.group(2))))
    for m in _EMPTY_RE.finditer(flat):
        hits.append((m.start(), "",          int(m.group(1))))
    hits.sort()
    return [(v, c) for _, v, c in hits]


def _group_rows(fields):
    """
    Split a flat (value, col) sequence into per-row dicts.

    A new row is detected when col_index resets backward
    (new col <= previous col) while the current row already has data.
    This handles both 10-column item rows and 4-column price rows.
    """
    rows, cur, prev_col = [], {}, -1
    for value, col in fields:
        if col <= prev_col and cur:
            rows.append(cur)
            cur = {}
        cur[col] = value
        prev_col = col
    if cur:
        rows.append(cur)
    return rows


# ── Public API ────────────────────────────────────────────────────────────────

_PRICE_SKIP_SKU = {"Артикул", "Артикул ", ""}  # header rows in prices.mxl


def parse_items(path):
    """
    Parse items.mxl → list of dicts using positional column order.

    The MXL format stores column indices unreliably for the last cell of each
    row (the closing number bleeds into the next row's separator token).  We
    therefore ignore col indices entirely and group the extracted values into
    fixed-size chunks of ITEM_NCOLS (10), skipping the leading header chunk.

    Values are verbatim 1C strings (Armenian / Russian / English as-is).
    """
    flat   = _load_flat(path)
    fields = _extract_fields(flat)
    values = [v for v, _ in fields]      # discard col indices

    result = []
    # Chunk 0 is the header row; data starts at chunk 1
    for chunk_start in range(ITEM_NCOLS, len(values), ITEM_NCOLS):
        chunk = values[chunk_start:chunk_start + ITEM_NCOLS]
        if len(chunk) < ITEM_NCOLS:
            break
        item = {ITEM_COL_NAMES[i]: chunk[i] for i in range(ITEM_NCOLS)}
        item["sku"] = item["sku"].strip()   # some SKUs have a leading space in 1C
        result.append(item)
    return result


def parse_prices(path):
    """
    Returns { sku: {"retail": float|None, "purchase": float|None} }.
    Retail price is at col 3; purchase price is at col N (N = row index).
    Price strings like "170,000.00" are converted to float.
    """
    flat   = _load_flat(path)
    fields = _extract_fields(flat)
    rows   = _group_rows(fields)

    def _to_float(raw):
        raw = raw.replace(",", "").strip()
        try:
            return float(raw) if raw else None
        except ValueError:
            return None

    prices = {}
    for row in rows:
        sku = row.get(1, "").strip()
        # Skip header/title rows: empty, known header strings, or Cyrillic-starting
        # (e.g. "Прайс-лист на May 6, 2026") — but keep real SKUs that contain spaces
        if not sku or sku in _PRICE_SKIP_SKU or (sku and ord(sku[0]) >= 0x0400):
            continue
        retail = _to_float(row.get(3, ""))
        prices[sku] = {"retail": retail}
    return prices


# ── CLI smoke-test ────────────────────────────────────────────────────────────

if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")

    items_path  = sys.argv[1] if len(sys.argv) > 1 else "items.mxl"
    prices_path = sys.argv[2] if len(sys.argv) > 2 else "prices.mxl"

    print("=== Items ===")
    items = parse_items(items_path)
    print(f"Total parsed: {len(items)}")
    for it in items[:5]:
        print(json.dumps(it, ensure_ascii=False))

    print("\n=== Prices ===")
    prices = parse_prices(prices_path)
    print(f"Total parsed: {len(prices)}")
    for sku, p in list(prices.items())[:5]:
        print(f"  {sku!r}: {p}")

    # Cross-check
    item_skus = {it["sku"] for it in items if it["sku"]}
    matched   = item_skus & set(prices)
    print(f"\nItems with SKU: {len(item_skus)}")
    print(f"Price entries:  {len(prices)}")
    print(f"SKU match (items & prices): {len(matched)}")

    # ── CSV export ────────────────────────────────────────────────────────────
    items_csv  = items_path.replace(".mxl", ".csv")
    prices_csv = prices_path.replace(".mxl", ".csv")

    with open(items_csv, "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.DictWriter(fh, fieldnames=ITEM_COL_NAMES)
        w.writeheader()
        w.writerows(items)
    print(f"\nWrote {items_csv}")

    with open(prices_csv, "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.writer(fh)
        w.writerow(["sku", "retail_price"])
        for sku, p in prices.items():
            w.writerow([sku, p["retail"]])
    print(f"Wrote {prices_csv}")
