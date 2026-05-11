# -*- coding: utf-8 -*-
"""
doc-resync-step1-fixes.py
Corrects three issues from the step1 run:
  1. D010 "Vigen Sargsyan" was wrongly renamed -> revert it
  2. D014 "Shengavit" prefix still present -> finish the rename
  3. Rebuild warehouse tree
"""
from __future__ import unicode_literals
import frappe

ABBR = "Inmed"
EM = "\u2014"


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


# ── Fix 1: revert wrongly-renamed D010 ───────────────────────────────────────
log("\n=== Fix 1: Revert D010 Sargsyan rename ===")

# The wrong rename stripped the first word (Vigen/Վіgen) from the doctor name.
# Strategy: find D010 under H006 (Astghik BK) by code-prefix lookup.
# The correct original warehouse_name (from warehouses.csv) is:
#   D010 — Վիգեն Սարգսյան Աստղիկ ԲԿ
CORRECT_D010_WH_NAME = "D010 — Վիգեն Սարգսյան Աստղիկ ԲԿ"

h006_name = frappe.db.get_value(
    "Warehouse",
    {"warehouse_name": ("like", "H006 —%")},
    "name",
)
log(f"  H006 = {h006_name!r}")

if h006_name:
    d010_astghik = frappe.db.get_all(
        "Warehouse",
        filters={"warehouse_name": ("like", "D010 —%"), "parent_warehouse": h006_name},
        fields=["name", "warehouse_name"],
    )
    log(f"  D010 under H006: {[w.warehouse_name for w in d010_astghik]}")
    for w in d010_astghik:
        correct_full = f"{CORRECT_D010_WH_NAME} - {ABBR}"
        if w.name == correct_full:
            log(f"  Already correct: {w.name!r}")
        else:
            rename_wh(w.name, CORRECT_D010_WH_NAME)
else:
    log("  ERROR: H006 not found")


# ── Fix 2: remove "Shengavit" prefix from D014 ───────────────────────────────
log("\n=== Fix 2: D014 Shengavit prefix removal ===")

# After step 1e, warehouse is: "D014 — Shengavit Khoren Petrosyan Astghik BK - Inmed"
# Target:                       "D014 — Khoren Petrosyan Astghik BK - Inmed"
#
# Strategy: find H006 (Astghik BK) by code prefix, then find D014 under it.
h006 = frappe.db.get_value(
    "Warehouse",
    {"warehouse_name": ("like", "H006 \u2014%")},
    "name",
)
log(f"  H006 = {h006!r}")

if h006:
    d014_candidates = frappe.db.get_all(
        "Warehouse",
        filters={"warehouse_name": ("like", "D014 \u2014%"), "parent_warehouse": h006},
        fields=["name", "warehouse_name"],
    )
else:
    # Fallback: all D014s — pick the one with the most tokens (has the extra prefix word)
    all_d014 = frappe.db.get_all(
        "Warehouse",
        filters={"warehouse_name": ("like", "D014 \u2014%")},
        fields=["name", "warehouse_name"],
    )
    log(f"  All D014s: {[w.warehouse_name for w in all_d014]}")
    d014_candidates = sorted(all_d014,
                             key=lambda w: len(w.warehouse_name.split()),
                             reverse=True)[:1]

log(f"  D014 candidates: {[w.warehouse_name for w in d014_candidates]}")

for w in d014_candidates:
    after_em = w.warehouse_name.split(EM, 1)[-1].strip()
    tokens = after_em.split()
    # Remove the first token (Shengavit city prefix)
    if len(tokens) > 1:
        new_short = " ".join(tokens[1:])
        new_wh_name = f"D014 {EM} {new_short}"
        log(f"  D014: {w.warehouse_name!r} -> {new_wh_name!r}")
        rename_wh(w.name, new_wh_name)
    else:
        log(f"  D014: only 1 token after dash, skipping: {w.warehouse_name!r}")


# ── Fix 3: rebuild warehouse nested-set tree ─────────────────────────────────
log("\n=== Fix 3: Rebuild warehouse tree ===")
from frappe.utils.nestedset import rebuild_tree as _rebuild_tree
import inspect
sig = inspect.signature(_rebuild_tree)
params = list(sig.parameters.keys())
log(f"  rebuild_tree signature params: {params}")
try:
    if len(params) >= 2:
        _rebuild_tree("Warehouse", "parent_warehouse")
    else:
        _rebuild_tree("Warehouse")
    frappe.db.commit()
    log("  rebuild_tree OK")
except Exception as e:
    log(f"  rebuild_tree failed: {e}")

log("\nDone.")
