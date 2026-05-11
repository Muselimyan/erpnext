# -*- coding: utf-8 -*-
"""
doc-resync-fix-h050-v2.py
Renames H050 and D150/D151/D152 using explicit Unicode escapes.

Wrong  (on server): H050 — Ֆanardzhyan OOАК
  Ֆ(U+0556) + Latin a-n-a-r-d-z-h-y-a-n + Latin OO + Cyrillic АК

Correct (user wants): H050 — Ֆanardzhyan OOАК
  Ֆ(U+0556) + Armenian անarjyan + Cyrillic ОО + Cyrillic АК
"""
from __future__ import unicode_literals
import frappe

ABBR = "Inmed"
EM   = "\u2014"

# Ֆ   ա    ն    ա    ր    ջ    յ    ա    ն
CORRECT_HOSP_SHORT = (
    "\u0556\u0561\u0576\u0561\u0580\u057b\u0575\u0561\u0576"
    " "
    "\u041e\u041e\u0410\u041a"   # Cyrillic ОО + Cyrillic АК
)


def log(msg):
    print(msg)


def rename_wh(old_full_name, new_wh_name):
    new_full_name = f"{new_wh_name} - {ABBR}"
    if frappe.db.exists("Warehouse", new_full_name):
        log(f"  SKIP (exists): {new_full_name!r}")
        return new_full_name
    frappe.rename_doc("Warehouse", old_full_name, new_full_name, force=True)
    frappe.db.set_value("Warehouse", new_full_name, "warehouse_name", new_wh_name, update_modified=False)
    frappe.db.commit()
    log(f"  Renamed: {old_full_name!r} -> {new_full_name!r}")
    return new_full_name


# ── Rename H050 ────────────────────────────────────────────────────────────────
log("\n=== Rename H050 ===")
h050_new_name    = f"H050 {EM} {CORRECT_HOSP_SHORT}"
h050_correct_full = f"{h050_new_name} - {ABBR}"

if frappe.db.exists("Warehouse", h050_correct_full):
    log(f"  H050 already correct: {h050_correct_full!r}")
    h050_new_full = h050_correct_full
else:
    row = frappe.db.get_value("Warehouse", {"warehouse_name": ("like", "H050 \u2014%")}, "name")
    if row:
        old_name = frappe.db.get_value("Warehouse", row, "warehouse_name")
        log(f"  Found H050: {old_name!r}")
        log(f"  Codepoints: {[hex(ord(c)) for c in old_name]}")
        h050_new_full = rename_wh(row, h050_new_name)
    else:
        log("  ERROR: H050 not found")
        h050_new_full = None

# ── Rename child doctors (D150/D151/D152) ──────────────────────────────────────
log("\n=== Rename children of H050 ===")
if h050_new_full:
    children = frappe.db.get_all(
        "Warehouse",
        filters={"parent_warehouse": h050_new_full},
        fields=["name", "warehouse_name"],
    )
    log(f"  Children: {len(children)}")
    for c in children:
        parts = c.warehouse_name.split(EM, 1)
        if len(parts) < 2:
            log(f"  SKIP: {c.warehouse_name!r}")
            continue
        code  = parts[0].strip()          # "D150"
        rest  = parts[1].strip()          # "Alalexsandr OldHospName"
        first = rest.split()[0]           # "Alalexsandr"
        new_wh_name = f"{code} {EM} {first} {CORRECT_HOSP_SHORT}"
        if c.name == f"{new_wh_name} - {ABBR}":
            log(f"  Already correct: {c.name!r}")
        else:
            log(f"  {c.warehouse_name!r} -> {new_wh_name!r}")
            rename_wh(c.name, new_wh_name)

# ── Rebuild tree ───────────────────────────────────────────────────────────────
log("\n=== Rebuild tree ===")
from frappe.utils.nestedset import rebuild_tree as _rt
import inspect
params = list(inspect.signature(_rt).parameters.keys())
_rt("Warehouse", "parent_warehouse") if len(params) >= 2 else _rt("Warehouse")
frappe.db.commit()
log("Done.")
