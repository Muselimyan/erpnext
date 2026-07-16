#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
deploy_items.py — Wipe all ERPNext Items and re-create from 1C MXL exports.

Run inside the Frappe container:
    bench --site 161.97.83.156 execute deploy_items.main

Or via runner wrapper:
    python3 -c "
      import frappe
      frappe.init('/home/frappe/frappe-bench/sites/161.97.83.156')
      frappe.connect()
      exec(open('/home/frappe/deploy_items.py').read())
      main()
      frappe.db.commit()
      frappe.destroy()
    "

Expects parse_mxl.py in the same directory (/home/frappe/).
Expects items.mxl and prices.mxl in /home/frappe/.
"""

import os
import sys

# ── Paths (inside container) ──────────────────────────────────────────────────
_DIR        = os.path.dirname(os.path.abspath(__file__)) if "__file__" in dir() else "/home/frappe"
ITEMS_MXL   = os.path.join(_DIR, "items.mxl")
PRICES_MXL  = os.path.join(_DIR, "prices.mxl")
SITE        = "161.97.83.156"
PRICE_LIST  = "Standard Selling"

# item_type value for expiry/batch-tracked items (Armenian: Ժամկետով ապրանքներ)
EXPIRY_TYPE = "Ժամկետով ապրանքներ"


# ── Helpers ───────────────────────────────────────────────────────────────────

def _ensure_custom_1c_code():
    """Create custom_1c_code field on Item if not already present."""
    if frappe.db.exists("Custom Field", "Item-custom_1c_code"):
        return
    cf = frappe.new_doc("Custom Field")
    cf.dt           = "Item"
    cf.fieldname    = "custom_1c_code"
    cf.label        = "1C Code"
    cf.fieldtype    = "Data"
    cf.insert_after = "item_code"
    cf.read_only    = 0
    cf.in_list_view = 0
    cf.insert(ignore_permissions=True)
    frappe.db.commit()
    print("  Created custom field: Item.custom_1c_code")


def _discover_vat_template():
    """Return the name of the 20% Item Tax Template for InMED, or None."""
    templates = frappe.db.get_all(
        "Item Tax Template",
        filters={"disabled": 0},
        fields=["name"],
    )
    # Prefer one that contains "20" in its name
    for t in templates:
        if "20" in t.name:
            return t.name
    return templates[0].name if templates else None


def _delete_all_items():
    """Remove all Item Price and Item records (SQL-level for speed)."""
    frappe.db.sql("DELETE FROM `tabItem Price`")
    frappe.db.sql("DELETE FROM `tabItem Tax`")
    frappe.db.sql("DELETE FROM `tabItem Barcode`")
    frappe.db.sql("DELETE FROM `tabUOM Conversion Detail`")
    frappe.db.sql("DELETE FROM `tabItem Reorder`")
    frappe.db.sql("DELETE FROM `tabItem Supplier`")
    # Stock ledger / bins depend on running items — clear them too
    frappe.db.sql("DELETE FROM `tabBin`")
    frappe.db.sql("DELETE FROM `tabStock Ledger Entry`")
    # Finally delete items
    frappe.db.sql("DELETE FROM `tabItem`")
    frappe.db.commit()


def _ensure_item_group(name):
    if not name or frappe.db.exists("Item Group", name):
        return
    ig = frappe.new_doc("Item Group")
    ig.item_group_name    = name
    ig.parent_item_group  = "All Item Groups"
    ig.insert(ignore_permissions=True)


def _create_item(row, vat_template):
    item_code = (row["sku"] or row["code_1c"] or "").strip()
    if not item_code:
        return None  # skip the 3 items with neither SKU nor 1C code

    is_expiry = (row["item_type"] == EXPIRY_TYPE)

    doc = frappe.new_doc("Item")
    doc.item_code               = item_code
    doc.item_name               = row["description"] or item_code
    doc.item_group              = row["group"] or "All Item Groups"
    doc.stock_uom               = "Nos"
    doc.is_stock_item           = 1
    doc.has_batch_no            = 1 if is_expiry else 0
    doc.create_new_batch_automatically = 0
    doc.has_expiry_date         = 1 if is_expiry else 0
    doc.custom_1c_code          = row["code_1c"]
    doc.hs_code                 = row["hs_code"]
    # import_tax_rate left blank — populate manually per Doc 17A

    if row["vat_rate"] == "20%" and vat_template:
        doc.append("taxes", {"item_tax_template": vat_template})

    doc.insert(ignore_permissions=True)
    return item_code


def _set_retail_price(item_code, retail):
    if not retail or retail <= 0:
        return
    ip = frappe.new_doc("Item Price")
    ip.item_code       = item_code
    ip.price_list      = PRICE_LIST
    ip.selling         = 1
    ip.currency        = "AMD"
    ip.price_list_rate = retail
    ip.insert(ignore_permissions=True)


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    sys.path.insert(0, _DIR)
    from parse_mxl import parse_items, parse_prices

    print("=" * 60)
    print("deploy_items.py")
    print("=" * 60)

    # ── Pre-flight ────────────────────────────────────────────────
    print("\n[0/4] Pre-flight checks...")
    _ensure_custom_1c_code()
    vat_template = _discover_vat_template()
    print(f"  VAT template (20%): {vat_template!r}")

    items  = parse_items(ITEMS_MXL)
    prices = parse_prices(PRICES_MXL)
    print(f"  Parsed: {len(items)} items, {len(prices)} price entries")

    # ── Step 1: Delete ────────────────────────────────────────────
    print("\n[1/4] Deleting all existing items and prices...")
    _delete_all_items()
    print("  Done.")

    # ── Step 2: Item Groups ───────────────────────────────────────
    print("\n[2/4] Creating item groups...")
    groups = sorted({row["group"] for row in items if row["group"]})
    for g in groups:
        _ensure_item_group(g)
    frappe.db.commit()
    print(f"  {len(groups)} groups ready.")

    # ── Step 3: Create Items ──────────────────────────────────────
    print("\n[3/4] Creating items...")
    created, skipped, errors = 0, 0, []

    for i, row in enumerate(items):
        try:
            code = _create_item(row, vat_template)
            if code:
                created += 1
            else:
                skipped += 1
        except Exception as e:
            errors.append((row.get("sku") or row.get("code_1c"), str(e)))

        if (i + 1) % 200 == 0:
            frappe.db.commit()
            print(f"  ... {i + 1}/{len(items)}")

    frappe.db.commit()
    print(f"  Created: {created}  Skipped (no code): {skipped}  Errors: {len(errors)}")
    if errors:
        print("  First errors:")
        for code, msg in errors[:5]:
            print(f"    {code}: {msg}")

    # ── Step 4: Retail Prices ─────────────────────────────────────
    print("\n[4/4] Setting retail prices (Standard Selling)...")
    price_set, price_skip = 0, 0

    for row in items:
        item_code = (row["sku"] or row["code_1c"] or "").strip()
        if not item_code:
            continue
        p = prices.get(item_code, {})
        retail = p.get("retail")
        if retail:
            try:
                _set_retail_price(item_code, retail)
                price_set += 1
            except Exception:
                price_skip += 1

    frappe.db.commit()
    print(f"  Prices set: {price_set}  Skipped (no price): {price_skip}")

    print("\n" + "=" * 60)
    print("deploy_items.py — COMPLETE")
    print("=" * 60)


if __name__ == "__main__":
    import frappe
    frappe.init(site=SITE, sites_path="/home/frappe/frappe-bench/sites")
    frappe.connect()
    try:
        main()
        frappe.db.commit()
    finally:
        frappe.destroy()
