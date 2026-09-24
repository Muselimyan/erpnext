# ==============================================================
# A1 PROBE (read-only): can ERPNext's own cost basis actually be used here?
#
# The proposed A1 fix is "stop costing from Standard Buying, use
# Sales Invoice Item.incoming_rate". That is only a swap if ERPNext actually
# POPULATES incoming_rate on these invoices. Dispatch invoices are created with
# update_stock = 0 and are not linked to a Delivery Note -- stock moves through
# custom Stock Entries instead -- so ERPNext may have no stock transaction to
# derive a cost from.
#
# This probe answers, from real data, before any code is written:
#   1. is incoming_rate populated on dispatch invoices at all?
#   2. do those invoices link to any stock document ERPNext could cost from?
#   3. does the item have a usable valuation_rate as a fallback?
#   4. how far off is the current Standard Buying basis?
#   5. is landed cost actually being applied (Landed Cost Vouchers exist)?
#
# Read-only. No writes, no rollback needed.
# ==============================================================
import frappe
def a1_probe():
    OUT = []
    def line(k, v):
        OUT.append("A1PROBE | {0:<44} | {1}".format(k, v))
    # ── 1. dispatch invoices and their incoming_rate ──────────────────
    sis = frappe.get_all("Sales Invoice", filters={"docstatus": 1}, fields=["name", "update_stock", "grand_total", "dispatch_case"], limit_page_length=0)
    line("submitted Sales Invoices (all)", len(sis))
    line("...carrying a dispatch_case", len([s for s in sis if s.dispatch_case]))
    if not sis:
        line("STOP", "no dispatch invoices to measure")
        print("A1PROBE_START")
        for o in OUT:
            print(o)
        print("A1PROBE_END")
        return
    upd = len([s for s in sis if int(s.update_stock or 0) == 1])
    line("...with update_stock = 1", "{0} of {1}".format(upd, len(sis)))
    names = [s.name for s in sis]
    rows = frappe.get_all("Sales Invoice Item", filters={"parent": ["in", names]}, fields=["name", "parent", "item_code", "qty", "rate", "incoming_rate"], limit_page_length=0)
    line("invoice lines total", len(rows))
    withir = [r for r in rows if float(r.incoming_rate or 0) > 0]
    line("lines with incoming_rate > 0", "{0} of {1}".format(len(withir), len(rows)))
    # ── 2. is there any stock document ERPNext could cost from? ───────
    dn = frappe.get_all("Delivery Note Item", filters={"against_sales_invoice": ["in", names]}, fields=["name"], limit_page_length=1)
    line("lines linked to a Delivery Note", len(dn))
    # ── 3. valuation fallback, and the current basis, side by side ────
    codes = list(set([r.item_code for r in rows if r.item_code]))
    line("distinct items invoiced", len(codes))
    have_val = 0
    have_buy = 0
    both = []
    for c in codes:
        v = frappe.db.get_value("Bin", {"item_code": c, "warehouse": "Main - Inmed"}, "valuation_rate")
        b = frappe.db.get_value("Item Price", {"item_code": c, "price_list": "Standard Buying"}, "price_list_rate")
        v = float(v or 0)
        b = float(b or 0)
        if v > 0:
            have_val += 1
        if b > 0:
            have_buy += 1
        if v > 0 and b > 0:
            both.append((c, v, b))
    line("items with a valuation_rate", "{0} of {1}".format(have_val, len(codes)))
    line("items with a Standard Buying price", "{0} of {1}".format(have_buy, len(codes)))
    line("items with BOTH (comparable)", len(both))
    if both:
        diffs = []
        for c, v, b in both:
            diffs.append(abs(v - b) / b * 100.0)
        diffs.sort()
        avg = sum(diffs) / len(diffs)
        line("valuation vs buying-price gap, mean", "{0:.1f}%".format(avg))
        line("valuation vs buying-price gap, median", "{0:.1f}%".format(diffs[len(diffs) // 2]))
        line("worst gap", "{0:.1f}%".format(diffs[-1]))
        for c, v, b in both[:4]:
            line("  sample {0}".format(c[:22]), "valuation={0:.2f} buying={1:.2f}".format(v, b))
    # ── 4. is landed cost actually in use? ────────────────────────────
    lcv = frappe.db.count("Landed Cost Voucher", {"docstatus": 1})
    pr = frappe.db.count("Purchase Receipt", {"docstatus": 1})
    line("submitted Landed Cost Vouchers", lcv)
    line("submitted Purchase Receipts", pr)
    line("VERDICT landed cost in use", "YES" if lcv > 0 else "NO - valuation is purchase price only")
    # ── 5. does the native Gross Profit report have a basis? ──────────
    line("VERDICT incoming_rate usable", "YES" if len(withir) > 0 else "NO - not populated on these invoices")
    line("VERDICT valuation_rate usable", "YES" if have_val > len(codes) * 0.8 else "PARTIAL - {0}/{1} items".format(have_val, len(codes)))
    print("A1PROBE_START")
    for o in OUT:
        print(o)
    print("A1PROBE_END")
a1_probe()
