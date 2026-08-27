# -*- coding: utf-8 -*-
"""
doc-resync-step1-fix-h050.py
Renames H050 and its child doctors to use the correct full Armenian name.
  Wrong:   Ֆanardzhyan OOАК   (Latin chars mixed in)
  Correct: Ֆanardzhyan OOАК   (fully Armenian/correct script)
"""
from __future__ import unicode_literals
import frappe

ABBR = "Inmed"
EM = "\u2014"

CORRECT_HOSP_SHORT = "Ֆanardzhyan OOАК"


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


# ── Step 1: rename H050 (find by code prefix, not by full name string) ────────
log("\n=== Rename H050 ===")

h050_new_name = f"H050 {EM} {CORRECT_HOSP_SHORT}"
h050_correct_full = f"{h050_new_name} - {ABBR}"

if frappe.db.exists("Warehouse", h050_correct_full):
    log(f"  H050 already correct: {h050_correct_full!r}")
    h050_new_full = h050_correct_full
else:
    # Find the current H050 (whatever its wrong name is) by code prefix
    row = frappe.db.get_value("Warehouse", {"warehouse_name": ("like", "H050 \u2014%")}, "name")
    if row:
        old_wh_name = frappe.db.get_value("Warehouse", row, "warehouse_name")
        log(f"  Found H050: {row!r}  (warehouse_name={old_wh_name!r})")
        h050_new_full = rename_wh(row, h050_new_name)
    else:
        log("  ERROR: H050 not found")
        h050_new_full = None


# ── Step 2: rename child doctors under H050 ──────────────────────────────────
log("\n=== Rename D150/D151/D152 (children of H050) ===")

if h050_new_full:
    children = frappe.db.get_all(
        "Warehouse",
        filters={"parent_warehouse": h050_new_full},
        fields=["name", "warehouse_name"],
    )
    log(f"  Children found: {len(children)}")

    for c in children:
        old_wh_name = c.warehouse_name
        # Extract the doctor's code (D###) and first personal name token after the em-dash.
        # Structure: "D### — <FirstName> <OldHospName>"
        # We reconstruct as: "D### — <FirstName> <CORRECT_HOSP_SHORT>"
        after_em = old_wh_name.split(EM, 1)
        if len(after_em) < 2:
            log(f"  SKIP (no em-dash): {old_wh_name!r}")
            continue
        code_part  = after_em[0].strip()          # "D150"
        rest       = after_em[1].strip()          # "Alalexsandr OldHospName"
        first_token = rest.split()[0]              # "Alalexsandr" (doctor personal name)
        new_wh_name = f"{code_part} {EM} {first_token} {CORRECT_HOSP_SHORT}"
        if c.name == f"{new_wh_name} - {ABBR}":
            log(f"  Already correct: {c.name!r}")
        else:
            log(f"  {old_wh_name!r} -> {new_wh_name!r}")
            rename_wh(c.name, new_wh_name)


# ── Step 3: rebuild tree ──────────────────────────────────────────────────────
log("\n=== Rebuild tree ===")
from frappe.utils.nestedset import rebuild_tree as _rt
import inspect
params = list(inspect.signature(_rt).parameters.keys())
if len(params) >= 2:
    _rt("Warehouse", "parent_warehouse")
else:
    _rt("Warehouse")
frappe.db.commit()
log("  Done.")
