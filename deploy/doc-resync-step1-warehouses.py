# -*- coding: utf-8 -*-
"""
doc-resync-step1-warehouses.py
Warehouse tree restructuring for customer resync (plan step 1).

Run on server:
  bench --site erpnext.am execute /path/to/doc-resync-step1-warehouses.py

Operations (in order):
  1a. Merge duplicate hospital groups (H005→H004, H026→H027, H048→H049, delete H038)
  1b. Convert H029 (group) → D### leaf doctor "Ахарոն" under H028
  1c. Create H050 Ֆanardzhyan OOAK hospital; convert H045/H046/H047 → D### doctors
  1d. Targeted name fixes (H020 typo, D122, D010, D014)
  1e. Strip commas from ALL warehouse names under Clients - Inmed
"""
from __future__ import unicode_literals
import re
import frappe

ABBR = "Inmed"          # company abbreviation used in " - Inmed" suffix
COMPANY = "InMED"       # company name
CLIENTS = "Clients - Inmed"
EM = "\u2014"           # — (em-dash used in all warehouse names)

# ── helpers ───────────────────────────────────────────────────────────────────

def log(msg):
    print(msg)


def get_wh(code):
    """Return warehouse dict {name, warehouse_name, parent_warehouse, is_group} by D###/H### code."""
    result = frappe.db.get_value(
        "Warehouse",
        {"warehouse_name": ("like", f"{code} {EM}%")},
        ["name", "warehouse_name", "parent_warehouse", "is_group"],
        as_dict=True,
    )
    return result


def rename_wh(old_full_name, new_wh_name):
    """Rename warehouse: updates PK and warehouse_name field. Returns new full name."""
    new_full_name = f"{new_wh_name} - {ABBR}"
    if frappe.db.exists("Warehouse", new_full_name):
        log(f"  SKIP rename (target exists): {new_full_name!r}")
        return new_full_name
    frappe.rename_doc("Warehouse", old_full_name, new_full_name, force=True)
    frappe.db.set_value("Warehouse", new_full_name, "warehouse_name", new_wh_name, update_modified=False)
    frappe.db.commit()
    log(f"  Renamed: {old_full_name!r}  ->  {new_full_name!r}")
    return new_full_name


def reparent_wh(child_full_name, new_parent_full_name):
    """Move warehouse to a new parent."""
    if not frappe.db.exists("Warehouse", child_full_name):
        log(f"  SKIP reparent (not found): {child_full_name!r}")
        return
    doc = frappe.get_doc("Warehouse", child_full_name)
    old_parent = doc.parent_warehouse
    doc.parent_warehouse = new_parent_full_name
    doc.save(ignore_permissions=True)
    frappe.db.commit()
    log(f"  Reparented: {child_full_name!r}  [{old_parent!r} -> {new_parent_full_name!r}]")


def set_group(wh_full_name, val):
    """Set is_group flag."""
    frappe.db.set_value("Warehouse", wh_full_name, "is_group", val, update_modified=False)
    frappe.db.commit()
    log(f"  is_group={val}: {wh_full_name!r}")


def delete_wh(wh_full_name):
    """Delete warehouse only if it has no children."""
    if not frappe.db.exists("Warehouse", wh_full_name):
        log(f"  SKIP delete (not found): {wh_full_name!r}")
        return
    kids = frappe.get_all("Warehouse", filters={"parent_warehouse": wh_full_name}, limit=1)
    if kids:
        log(f"  SKIP delete (has children): {wh_full_name!r}")
        return
    frappe.delete_doc("Warehouse", wh_full_name, force=True, ignore_permissions=True)
    frappe.db.commit()
    log(f"  Deleted: {wh_full_name!r}")


def create_group_wh(wh_name, parent_full_name):
    """Create a new group warehouse. Returns full name."""
    full = f"{wh_name} - {ABBR}"
    if frappe.db.exists("Warehouse", full):
        log(f"  EXISTS: {full!r}")
        return full
    doc = frappe.get_doc({
        "doctype": "Warehouse",
        "warehouse_name": wh_name,
        "parent_warehouse": parent_full_name,
        "company": COMPANY,
        "is_group": 1,
    })
    doc.insert(ignore_permissions=True)
    frappe.db.commit()
    log(f"  Created group: {full!r}")
    return full


def wh_short_name(wh):
    """Extract short name from warehouse dict (strips 'X### — ' prefix)."""
    return wh.warehouse_name.split(EM, 1)[-1].strip()


# ── detect next available D### and H### codes ─────────────────────────────────

all_wh_names = frappe.get_all("Warehouse", fields=["warehouse_name"])
d_nums = sorted([int(m.group(1)) for w in all_wh_names
                 for m in [re.match(r"^D(\d+)", w.warehouse_name or "")] if m])
h_nums = sorted([int(m.group(1)) for w in all_wh_names
                 for m in [re.match(r"^H(\d+)", w.warehouse_name or "")] if m])

_nd = [d_nums[-1] + 1 if d_nums else 149]
_nh = [h_nums[-1] + 1 if h_nums else 50]
log(f"Max existing D={d_nums[-1] if d_nums else 0:03d}, H={h_nums[-1] if h_nums else 0:03d}")
log(f"Next alloc:  D{_nd[0]:03d}, H{_nh[0]:03d}")


def alloc_d():
    code = f"D{_nd[0]:03d}"
    _nd[0] += 1
    return code


def alloc_h():
    code = f"H{_nh[0]:03d}"
    _nh[0] += 1
    return code


# ══════════════════════════════════════════════════════════════════════════════
# STEP 1a — merge duplicate hospital groups
# ══════════════════════════════════════════════════════════════════════════════
log("\n=== Step 1a: Merge duplicate hospital groups ===")

# H004 / H005 — both "Առաջین Հivandanots" (case-only duplicate)
#   Move D049 (Մenua) from H005 → H004, then delete H005
r_h004 = get_wh("H004")
r_h005 = get_wh("H005")
r_d049 = get_wh("D049")
if r_d049 and r_h004:
    reparent_wh(r_d049.name, r_h004.name)
if r_h005:
    delete_wh(r_h005.name)

# H026 / H027 — both Kapan (Կапан / Կапан ԲK)
#   Move D018 (Sariq Atahjanyan) from H026 → H027 (Kapan BK), delete H026
r_h026 = get_wh("H026")
r_h027 = get_wh("H027")
r_d018 = get_wh("D018")
if r_d018 and r_h027:
    reparent_wh(r_d018.name, r_h027.name)
if r_h026:
    delete_wh(r_h026.name)

# H048 / H049 — same orthopaedic clinic (case + minor spelling)
#   Move D144 (Serob) from H048 → H049, delete H048
r_h048 = get_wh("H048")
r_h049 = get_wh("H049")
r_d144 = get_wh("D144")
if r_d144 and r_h049:
    reparent_wh(r_d144.name, r_h049.name)
if r_h048:
    delete_wh(r_h048.name)

# H038 — empty duplicate of H039 (Spitak BK); just delete
r_h038 = get_wh("H038")
if r_h038:
    delete_wh(r_h038.name)


# ══════════════════════════════════════════════════════════════════════════════
# STEP 1b — convert H029 (group, 0 children) → D### leaf doctor under H028
# ══════════════════════════════════════════════════════════════════════════════
log("\n=== Step 1b: H029 -> D### doctor under H028 ===")

r_h029 = get_wh("H029")
r_h028 = get_wh("H028")

if r_h029 and r_h028:
    # H029 warehouse_name e.g. "H029 — Հоктemberyan BK Аharon"
    # Extract doctor name = last token after the em-dash part
    after_em = r_h029.warehouse_name.split(EM, 1)[-1].strip()
    # after_em = "Hoktemberyan BK Aharon"  (all Armenian)
    tokens = after_em.split()
    doctor_name = tokens[-1]   # last word = doctor name ("Aharon" in Armenian)

    h028_short = wh_short_name(r_h028)    # "Hoktemberyan BK" in Armenian

    d_code = alloc_d()
    new_wh_name = f"{d_code} {EM} {doctor_name} {h028_short}"
    log(f"  New doctor warehouse_name: {new_wh_name!r}")

    new_name = rename_wh(r_h029.name, new_wh_name)
    set_group(new_name, 0)
    reparent_wh(new_name, r_h028.name)
else:
    log(f"  SKIP: H029={r_h029}, H028={r_h028}")


# ══════════════════════════════════════════════════════════════════════════════
# STEP 1c — create H050 Ֆanardzhyan OOАК hospital
#           convert H045 / H046 / H047 → D### leaf doctors under H050
# ══════════════════════════════════════════════════════════════════════════════
log("\n=== Step 1c: Create Ֆanardzhyan OOAK hospital + convert H045/H046/H047 ===")

# New hospital name (user-provided Armenian text)
NEW_HOSP_SHORT = "Ֆanardzhyan OOАК"   # will be prefixed with H050 —
h_code = alloc_h()
new_hosp_wh_name = f"{h_code} {EM} {NEW_HOSP_SHORT}"
new_hosp_full = create_group_wh(new_hosp_wh_name, CLIENTS)

for src_code in ("H045", "H046", "H047"):
    r_src = get_wh(src_code)
    if not r_src:
        log(f"  SKIP: {src_code} not found")
        continue

    # Extract doctor name = last token (e.g. "Aleksandr", "Karapet", "Mamikon")
    after_em = r_src.warehouse_name.split(EM, 1)[-1].strip()
    tokens = after_em.split()
    doctor_name = tokens[-1]

    d_code = alloc_d()
    new_wh_name = f"{d_code} {EM} {doctor_name} {NEW_HOSP_SHORT}"
    log(f"  Converting {src_code}: {new_wh_name!r}")

    new_name = rename_wh(r_src.name, new_wh_name)
    set_group(new_name, 0)
    reparent_wh(new_name, new_hosp_full)


# ══════════════════════════════════════════════════════════════════════════════
# STEP 1d — targeted name fixes
# ══════════════════════════════════════════════════════════════════════════════
log("\n=== Step 1d: Targeted name fixes ===")

# D010: remove the leading city word ("Yeghegnadzzor" = Yegheghnadzzor in Armenian)
#       "D010 — Yeghegnadzzor Armenak Bdoyan Aradjin Hivandanoc"
#    -> "D010 — Armenak Bdoyan Aradjin Hivandanoc"
r_d010 = get_wh("D010")
# NOTE: there are two D010 warehouses in the data (different hospitals).
# We want the one containing "Yeghegnadzzor" (Եghegnadzzor) in the name.
d010_candidates = frappe.db.get_all(
    "Warehouse",
    filters=[["warehouse_name", "like", "D010 %"], ["warehouse_name", "like", "%Yeghegna%"]],
    fields=["name", "warehouse_name"],
)
# Fallback: also try with the Armenian letter sequence that spells Yeghegnadzzor
if not d010_candidates:
    d010_candidates = frappe.db.get_all(
        "Warehouse",
        filters=[["warehouse_name", "like", "D010 %"]],
        fields=["name", "warehouse_name"],
    )
    # Filter to those whose after-dash part has >3 tokens (the one with the prefix)
    d010_candidates = [w for w in d010_candidates
                       if len(w.warehouse_name.split(EM, 1)[-1].strip().split()) > 3]

for w in d010_candidates:
    after_em = w.warehouse_name.split(EM, 1)[-1].strip()  # "Yeghegnadzzor Armenak Bdoyan Aradjin Hivandanoc"
    parts = after_em.split(None, 1)                         # ["Yeghegnadzzor", "Armenak Bdoyan Aradjin Hivandanoc"]
    if len(parts) < 2:
        log(f"  SKIP D010 (unexpected format): {w.warehouse_name!r}")
        continue
    new_wh_name = f"D010 {EM} {parts[1]}"
    log(f"  D010 fix: {w.warehouse_name!r} -> {new_wh_name!r}")
    rename_wh(w.name, new_wh_name)

# D014: remove "Shengavit ," prefix
#       "D014 — Shengavit ,Khoren Petrosyan Astghik BK"
#    -> "D014 — Khoren Petrosyan Astghik BK"
d014_candidates = frappe.db.get_all(
    "Warehouse",
    filters=[["warehouse_name", "like", "D014 %"], ["warehouse_name", "like", "%, %"]],
    fields=["name", "warehouse_name"],
)
for w in d014_candidates:
    after_em = w.warehouse_name.split(EM, 1)[-1].strip()  # "Shengavit ,Khoren Petrosyan Astghik BK"
    # Remove everything up to and including the comma+space
    if "," in after_em:
        after_comma = after_em.split(",", 1)[-1].strip()   # "Khoren Petrosyan Astghik BK"
        new_wh_name = f"D014 {EM} {after_comma}"
        log(f"  D014 fix: {w.warehouse_name!r} -> {new_wh_name!r}")
        rename_wh(w.name, new_wh_name)

# H020 + D122: fix typo in "Yeghegnafdzzor" -> correct spelling from D010's sibling
#   Strategy: fetch the corrected D010 warehouse (after step above) and extract
#   the correct form of Yeghegnadzzor to use in H020/D122 rename.
#   Simpler: just strip the first word from H020 name (the wrong spelling) and
#   replace with the correct Armenian word we extract from D010-sibling, OR
#   we do a direct fix via known Armenian char substitution.
#
#   The typo is: the Armenian word has an extra letter "փ" (U+0583) inserted.
#   Correct: Եղեgnadzzor (without the extra character)
#   The Unicode fix: remove U+0583 (փ) from the name if present.
TYPO_CHAR = "\u0583"   # Armenian small letter piwr — the extra character in the typo

r_h020 = get_wh("H020")
if r_h020 and TYPO_CHAR in r_h020.warehouse_name:
    fixed_wh_name = r_h020.warehouse_name.replace(TYPO_CHAR, "")
    log(f"  H020 typo fix: {r_h020.warehouse_name!r} -> {fixed_wh_name!r}")
    rename_wh(r_h020.name, fixed_wh_name)
elif r_h020:
    log(f"  H020: no typo char found, current name: {r_h020.warehouse_name!r}")

r_d122 = get_wh("D122")
if r_d122:
    fixed_wh_name = r_d122.warehouse_name.replace(TYPO_CHAR, "").replace(",", "").replace("  ", " ")
    log(f"  D122 fix: {r_d122.warehouse_name!r} -> {fixed_wh_name!r}")
    if fixed_wh_name != r_d122.warehouse_name:
        rename_wh(r_d122.name, fixed_wh_name)


# ══════════════════════════════════════════════════════════════════════════════
# STEP 1e — strip commas from ALL warehouse names under Clients - Inmed
# ══════════════════════════════════════════════════════════════════════════════
log("\n=== Step 1e: Strip commas from all warehouse names ===")

# Fetch all warehouses whose name ends in " - Inmed" and have a comma
all_inmed = frappe.db.get_all(
    "Warehouse",
    filters={"name": ("like", "% - Inmed")},
    fields=["name", "warehouse_name"],
)

fixed_count = 0
for w in all_inmed:
    if "," not in (w.warehouse_name or ""):
        continue
    new_wh_name = re.sub(r"\s*,\s*", " ", w.warehouse_name).strip()
    new_wh_name = re.sub(r" {2,}", " ", new_wh_name)   # collapse double spaces
    if new_wh_name == w.warehouse_name:
        continue
    log(f"  Comma fix: {w.warehouse_name!r} -> {new_wh_name!r}")
    rename_wh(w.name, new_wh_name)
    fixed_count += 1

log(f"  Total comma fixes: {fixed_count}")


# ══════════════════════════════════════════════════════════════════════════════
# FINAL — rebuild Frappe nested-set tree
# ══════════════════════════════════════════════════════════════════════════════
log("\n=== Rebuilding Warehouse tree ===")
frappe.utils.nestedset.rebuild_tree("Warehouse", "parent_warehouse")
frappe.db.commit()
log("Done.")
