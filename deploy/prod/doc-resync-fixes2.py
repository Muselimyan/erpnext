# -*- coding: utf-8 -*-
"""
doc-resync-fixes2.py
Fix 1 — H050 abbreviation: Cyrillic ООАК → Armenian OOТK
         Armenian:  Ö(U+0548 VEH) + ö(U+0578 VO) + Ä(U+0531 AYB) + Κ(U+053F KEN)
         = the Armenian digraph Ö (U/OU sound) + Ä + Κ

Fix 2 — D138: strip "Тhиъ 2 бк " junk prefix from doctor name
         "D138 — Тhиъ 2 бк Эдик Тоноян ԲКН" → "D138 — Эдик Тоноян ԲКН"
"""
from __future__ import unicode_literals
import frappe

ABBR = "Inmed"
EM   = "\u2014"   # em-dash

# Armenian characters:
#   Ö = U+0548 (ARMENIAN CAPITAL LETTER VEH)  — first part of Ö digraph
#   ö = U+0578 (ARMENIAN SMALL LETTER VO)     — second part of Ö digraph
#   Ä = U+0531 (ARMENIAN CAPITAL LETTER AYB)
#   Κ = U+053F (ARMENIAN CAPITAL LETTER KEN)
CORRECT_ABBR       = "\u0548\u0578\u0531\u053f"   # OOТK
FANARJYAN_AM       = "\u0556\u0561\u0576\u0561\u0580\u057b\u0575\u0561\u0576"  # Ö
CORRECT_HOSP_SHORT = f"{FANARJYAN_AM} {CORRECT_ABBR}"


def log(msg):
    print(msg)


def rename_wh(old_full, new_wh_name):
    new_full = f"{new_wh_name} - {ABBR}"
    if old_full == new_full:
        log(f"  Already correct: {new_full!r}")
        return new_full
    if frappe.db.exists("Warehouse", new_full):
        log(f"  SKIP (target exists): {new_full!r}")
        return new_full
    frappe.rename_doc("Warehouse", old_full, new_full, force=True)
    frappe.db.set_value("Warehouse", new_full, "warehouse_name", new_wh_name, update_modified=False)
    frappe.db.commit()
    log(f"  Renamed: {old_full!r}")
    log(f"       ->: {new_full!r}")
    return new_full


# ══════════════════════════════════════════════════════════════════════════════
# FIX 1 — H050 abbreviation
# ══════════════════════════════════════════════════════════════════════════════
log("\n=== FIX 1: H050 abbreviation ===")
h050_new_name     = f"H050 {EM} {CORRECT_HOSP_SHORT}"
h050_correct_full = f"{h050_new_name} - {ABBR}"

log(f"  Target name : {h050_new_name!r}")
log(f"  Target abbr codepoints: {[hex(ord(c)) for c in CORRECT_ABBR]}")

if frappe.db.exists("Warehouse", h050_correct_full):
    log("  H050 already correct.")
    h050_new_full = h050_correct_full
else:
    row = frappe.db.get_value("Warehouse", {"warehouse_name": ("like", "H050 \u2014%")}, "name")
    if row:
        old_wh = frappe.db.get_value("Warehouse", row, "warehouse_name")
        log(f"  Found H050: {old_wh!r}")
        log(f"  Current abbr codepoints: {[hex(ord(c)) for c in old_wh.split()[-1]]}")
        h050_new_full = rename_wh(row, h050_new_name)
    else:
        log("  ERROR: H050 not found")
        h050_new_full = None

# Fix children D150/D151/D152
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
        code        = parts[0].strip()
        first_token = parts[1].strip().split()[0]
        new_wh_name = f"{code} {EM} {first_token} {CORRECT_HOSP_SHORT}"
        rename_wh(c.name, new_wh_name)

# ══════════════════════════════════════════════════════════════════════════════
# FIX 2 — D138: strip junk prefix "Тhиъ 2 бк "
# ══════════════════════════════════════════════════════════════════════════════
log("\n=== FIX 2: D138 doctor name cleanup ===")

row138 = frappe.db.get_value("Warehouse", {"warehouse_name": ("like", "D138 \u2014%")}, "name")
if row138:
    wh_name = frappe.db.get_value("Warehouse", row138, "warehouse_name")
    log(f"  Found: {wh_name!r}")
    after_em = wh_name.split(EM, 1)[1].strip()  # "Тhиъ 2 бк Эдик Тоноян ԲКН"
    tokens   = after_em.split()                  # ["Тhиъ","2","бк","Эдик","Тоноян","ԲКН"]
    log(f"  Tokens: {tokens}")
    # Drop the first 3 tokens ("Тhиъ 2 бк") and keep the rest
    new_doctor_part = " ".join(tokens[3:])        # "Эдик Тоноян ԲКН"
    new_wh_name138  = f"D138 {EM} {new_doctor_part}"
    log(f"  New name: {new_wh_name138!r}")
    rename_wh(row138, new_wh_name138)
else:
    log("  D138 not found (may already be renamed)")

# ══════════════════════════════════════════════════════════════════════════════
# Rebuild tree
# ══════════════════════════════════════════════════════════════════════════════
log("\n=== Rebuild tree ===")
from frappe.utils.nestedset import rebuild_tree as _rt
import inspect
params = list(inspect.signature(_rt).parameters.keys())
_rt("Warehouse", "parent_warehouse") if len(params) >= 2 else _rt("Warehouse")
frappe.db.commit()
log("Done.")
