# -*- coding: utf-8 -*-
"""
doc-resync-fix-h050-abbr.py
Changes H050 abbreviation from Cyrillic ООАК to Armenian UTUTAК.

Current (wrong):  Ֆanardzhyan ООAK   (Cyrillic О О А К)
Correct:          Ֆanardzhyan OOТK   (Armenian Ու Ա Կ)

Armenian characters used:
  Ö U+0548  ARMENIAN CAPITAL LETTER VEH  (first part of Ö digraph)
  Ö U+0578  ARMENIAN SMALL LETTER VO     (second part of Ö digraph)
  Ä U+0531  ARMENIAN CAPITAL LETTER AYB  (A sound)
  Κ U+053F  ARMENIAN CAPITAL LETTER KEN  (K sound)
"""
from __future__ import unicode_literals
import frappe

ABBR = "Inmed"
EM   = "\u2014"

# Armenian characters for OOТK  =  Ö(U+0548) + Ö(U+0578) + Ä(U+0531) + Κ(U+053F)
CORRECT_ABBR = "\u0548\u0578\u0531\u053f"   # OOТK in Armenian

# Armenian name of Fanarjyan (already correct on server)
FANARJYAN_AM = "\u0556\u0561\u0576\u0561\u0580\u057b\u0575\u0561\u0576"  # Ֆanardzhyan

CORRECT_HOSP_SHORT = f"{FANARJYAN_AM} {CORRECT_ABBR}"   # Ֆanardzhyan OOТK


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
h050_new_name     = f"H050 {EM} {CORRECT_HOSP_SHORT}"
h050_correct_full = f"{h050_new_name} - {ABBR}"

log(f"  Target: {h050_correct_full!r}")
log(f"  Target codepoints (short): {[hex(ord(c)) for c in CORRECT_HOSP_SHORT]}")

if frappe.db.exists("Warehouse", h050_correct_full):
    log(f"  H050 already correct.")
    h050_new_full = h050_correct_full
else:
    row = frappe.db.get_value("Warehouse", {"warehouse_name": ("like", "H050 \u2014%")}, "name")
    if row:
        old_wh = frappe.db.get_value("Warehouse", row, "warehouse_name")
        log(f"  Found: {old_wh!r}")
        h050_new_full = rename_wh(row, h050_new_name)
    else:
        log("  ERROR: H050 not found")
        h050_new_full = None

# ── Rename child doctors ───────────────────────────────────────────────────────
log("\n=== Rename D150/D151/D152 ===")
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
            continue
        code        = parts[0].strip()        # "D150"
        first_token = parts[1].strip().split()[0]  # doctor's first name
        new_wh_name = f"{code} {EM} {first_token} {CORRECT_HOSP_SHORT}"
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
