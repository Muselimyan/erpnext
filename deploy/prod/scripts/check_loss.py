import sys
sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, 'c:/Users/Vahe/CascadeProjects/erpnext/deploy')
from parse_mxl import parse_items, _load_flat, _extract_fields, _group_rows, _PRICE_SKIP_SKU

items = parse_items('c:/Users/Vahe/CascadeProjects/erpnext/1c/items.mxl')

# 1. Items with spaces in their SKU
items_sku_with_spaces = [it for it in items if it['sku'] and ' ' in it['sku']]
print(f"Items whose SKU contains a space: {len(items_sku_with_spaces)}")
for it in items_sku_with_spaces[:10]:
    print(f"  sku={it['sku']!r}  desc={it['description'][:50]}")

# 2. Check price rows we're currently filtering with " " in sku
flat = _load_flat('c:/Users/Vahe/CascadeProjects/erpnext/1c/prices.mxl')
fields = _extract_fields(flat)
rows = _group_rows(fields)
dropped = []
for row in rows:
    sku = row.get(1, '').strip()
    if sku and sku not in _PRICE_SKIP_SKU and ' ' in sku:
        dropped.append(sku)
print(f"\nPrice rows dropped by space-filter: {len(dropped)}")
for s in dropped[:10]:
    print(f"  {s!r}")

# 3. Check: do any dropped price SKUs match a real item SKU?
item_skus = {it['sku'] for it in items if it['sku']}
overlap = [s for s in dropped if s in item_skus]
print(f"\nDropped price SKUs that match an item: {len(overlap)}")
for s in overlap:
    print(f"  {s!r}")
