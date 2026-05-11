# -*- coding: utf-8 -*-
"""
generate_customers_preview.py
Builds customers-preview.csv from the live warehouse tree.
Run inside frappe-backend-1 via run_step1.sh runner.
Output: /tmp/customers-preview.csv (UTF-8 with BOM for Excel compat)
"""
import csv
import frappe

EM = "\u2014"
CLIENTS_PARENT = "Clients - Inmed"
OUT_PATH = "/tmp/customers-preview.csv"

def log(msg):
    print(msg)

def get_code(warehouse_name):
    import re
    m = re.match(r'^([DH]\d+)', warehouse_name)
    return m.group(1) if m else ""

def get_short_name(warehouse_name):
    """'H001 — Foo' -> 'Foo'"""
    idx = warehouse_name.find(EM)
    return warehouse_name[idx+1:].strip() if idx >= 0 else warehouse_name

def get_doctor_name(doctor_wh_name, hospital_short):
    """Strip code prefix and optional hospital suffix."""
    after = doctor_wh_name
    # Remove "D### — " prefix
    idx = after.find(EM)
    if idx >= 0:
        after = after[idx+1:].strip()
    # Remove hospital short name suffix if present
    if hospital_short and after.endswith(hospital_short):
        after = after[:-len(hospital_short)].strip()
    return after

# ── Fetch warehouse tree ───────────────────────────────────────────────────────
log("Querying warehouses...")
all_wh = frappe.db.get_all(
    "Warehouse",
    fields=["name", "warehouse_name", "is_group", "parent_warehouse"],
    limit_page_length=0,
)

# Build hospital map: full_name -> doc
hosp_map = {w.name: w for w in all_wh
            if w.parent_warehouse == CLIENTS_PARENT and w.is_group == 1}

# Build doctor list: children of hospitals
doctors = [w for w in all_wh
           if w.parent_warehouse in hosp_map and w.is_group == 0]

log(f"  Hospitals: {len(hosp_map)}")
log(f"  Doctors:   {len(doctors)}")

# ── Build rows ─────────────────────────────────────────────────────────────────
rows = []

# Hospital rows
for h in sorted(hosp_map.values(), key=lambda w: w.warehouse_name):
    code       = get_code(h.warehouse_name)
    short_name = get_short_name(h.warehouse_name)
    cust_name  = h.warehouse_name  # customer_name = warehouse_name exactly
    rows.append({
        "client_code":       code,
        "customer_name":     cust_name,
        "client_kind":       "Hospital",
        "customer_group":    "Commercial",
        "hospital":          "",
        "doctor_name":       "",
        "debt_threshold_amd": 0,
        "is_provisional":    1,
    })

# Doctor rows
hosp_short_lookup = {name: get_short_name(doc.warehouse_name) for name, doc in hosp_map.items()}

for d in sorted(doctors, key=lambda w: w.warehouse_name):
    code         = get_code(d.warehouse_name)
    hosp_full    = d.parent_warehouse
    hosp_short   = hosp_short_lookup.get(hosp_full, "")
    hosp_cust    = hosp_full.replace(" - Inmed", "")  # hospital customer_name
    doctor_name  = get_doctor_name(d.warehouse_name, hosp_short)
    cust_name    = d.warehouse_name  # customer_name = warehouse_name exactly
    rows.append({
        "client_code":       code,
        "customer_name":     cust_name,
        "client_kind":       "Doctor",
        "customer_group":    "Individual",
        "hospital":          hosp_cust,
        "doctor_name":       doctor_name,
        "debt_threshold_amd": 0,
        "is_provisional":    1,
    })

# ── Write CSV (UTF-8 with BOM) ─────────────────────────────────────────────────
FIELDS = ["client_code","customer_name","client_kind","customer_group",
          "hospital","doctor_name","debt_threshold_amd","is_provisional"]

with open(OUT_PATH, "w", encoding="utf-8-sig", newline="") as f:
    w = csv.DictWriter(f, fieldnames=FIELDS)
    w.writeheader()
    w.writerows(rows)

log(f"Written: {OUT_PATH}  ({len(rows)} rows)")
log(f"  Hospitals: {sum(1 for r in rows if r['client_kind']=='Hospital')}")
log(f"  Doctors:   {sum(1 for r in rows if r['client_kind']=='Doctor')}")
