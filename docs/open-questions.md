# Open Questions (Parking Lot)

## Purpose
This file is a running list of open operational decisions that we want to answer later without losing track.

---

## Doc 06 — Item Catalog and Variants
### Pack-breaking policy: which items are pack-breakable?
Question:
- Which categories/items do you **actually break** from a purchase pack/box into single units during day-to-day operations?

Reality note:
- You already have a small number of products where you buy boxes and sell singles, and you currently maintain singles as separate Items.

Decision needed:
- For each relevant category/item family, classify it as either:
  - `Never break packs` (stock + sales happen only in pack/box UOM), or
  - `Pack-breakable` (we will define and enforce a conversion policy).

Answer: Will anser when filling in data

Decision:
- For pack-breakable items that require batch/expiry traceability, migrate to the “single Item + UOM conversion” model (Stock UOM = single; Purchase UOM = box; 1 box = N singles) instead of separate box vs single Items.

Notes / examples to consider when answering:
- Items like implants sold individually often behave like `Nos` already.
- Items like gloves or gauze may be either `Box`-only or sometimes split, depending on reality.

---

All other questions that were previously parked here have been answered and integrated into the relevant docs.