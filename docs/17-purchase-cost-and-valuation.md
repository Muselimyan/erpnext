# Doc 17 — Purchase Flow with Costing and Valuation

## 1. Purpose

This document defines how InMED tracks the **true cost** of purchased inventory — not just the supplier price, but the fully landed cost including transportation, import taxes, and other charges. It extends Doc 07 (Basic P2P) with the costing layer.

**What this doc adds over Doc 07:**
- Landed Cost Voucher (LCV) step after receiving
- Valuation Rate: what it is, when it is set, and how it flows downstream
- Import tax automation via HS code on Item
- Batch tracking policy for cost isolation (supported, not mandatory)
- Currency / exchange rate handling at shipment time

**Non-goals:**
- Step-by-step ERPNext configuration (see Doc 17A)
- Reorder thresholds or PO preparation rules (Doc 08)
- Procurement status tracking during transit (Doc 07.1)

---

## 2. Core Concepts

### 2.1 Valuation Rate

The **Valuation Rate** is ERPNext's per-unit cost for an item in the warehouse. It is the number that flows into Cost of Goods Sold when an item is consumed or sold.

Rules:
- Valuation Rate is set automatically at the time of receiving (Purchase Receipt).
- It is re-calculated when a Landed Cost Voucher is applied to a receipt.
- The result is: `(purchase price + all landed charges) / received quantity`.
- **This is the authoritative cost price.** Do not maintain a separate "cost price" field elsewhere.

### 2.2 Landed Cost Voucher (LCV)

An LCV is the document that adds charges beyond the supplier price to a received shipment. It references one or more Purchase Receipts and lists additional charges (freight, import duty, other fees). ERPNext distributes these charges across the received items and recalculates their Valuation Rate.

An LCV is created **after** the Purchase Receipt, before or at the same time as the Purchase Invoice.

### 2.3 Batch Tracking and Cost Isolation

When an item is batch-tracked, each batch retains its own Valuation Rate. This means:
- Items received in January at USD 50/unit (after landed cost) and items received in March at USD 60/unit remain separate in stock.
- When March stock is consumed, COGS reflects the March cost — not a blend.
- This is called **per-lot cost isolation**.

Batch tracking is **supported but not mandatory** across all items:
- Items already batch-tracked for expiry automatically get per-lot cost isolation.
- Items not tracked by batch use **Moving Average** valuation — all stock of the item is blended at one average cost.
- The batch tracking policy per item is a decision made in the Item master (Doc 06).

### 2.4 Serial Tracking and Cost Isolation

Serial-tracked items are isolated by definition — each unit has its own serial number and its own Valuation Rate. No additional action is needed; cost isolation is automatic.

---

## 3. Item Master Additions for Costing

Two fields must be maintained on each Item that is imported (purchased internationally):

| Field | Type | Purpose |
|---|---|---|
| `hs_code` | Text | Harmonized System commodity code; determines import tax category |
| `import_tax_rate` | Percent | The fixed import tax rate applicable to this item's HS code |

Rules:
- `hs_code` is set once when the item is created and changes only when the regulatory classification changes.
- `import_tax_rate` is derived from the HS code and is treated as fixed. It does not change per shipment unless the regulation changes.
- At LCV creation, the import duty charge for a shipment is pre-calculated as: `sum of (item line value × import_tax_rate)` across all received items.
- The purchasing or accounting user confirms or overrides the pre-filled import duty amount before submitting the LCV.

---

## 4. Purchase Flow with Costing

### 4.1 Step 1 — Purchase Order

No change from Doc 07. The PO captures intended quantities and agreed supplier prices. Director approval is required before submission.

Costing note: the supplier unit price on the PO line is the **base purchase price only** — it does not include transport or import costs.

### 4.2 Step 2 — Purchase Receipt

The Purchase Receipt is the moment inventory enters the warehouse and stock balances increase.

At this step:
- **Received quantity** must match physical reality, not the PO quantity (partial deliveries are normal).
- **Batch number** must be assigned for any batch-tracked item. Options:
  - Use the supplier's lot/batch number printed on packaging.
  - Use a system-generated naming series (e.g., `LOT-YYYY-#####`).
- **Serial number(s)** must be assigned for serial-tracked items.
- **Expiry date** must be entered for all batch-tracked items (expiry enforcement is already active — see `Purchase Receipt-before-submit-main-inmed-expiry` script).

After submission, items are in stock at the **preliminary Valuation Rate** = supplier unit price from the receipt line. This rate will be revised upward by the LCV.

### 4.3 Step 3 — Landed Cost Voucher

The LCV is the central document for computing the true cost of a shipment. It must be created **for every import purchase** that has charges beyond the supplier price. It is optional for purely local purchases with no additional charges.

#### 4.3.1 LCV Structure

| Section | Content |
|---|---|
| **Purchase Receipts** | One or more receipts covered by this LCV (usually one per shipment) |
| **Charges** | One row per charge type (see 4.3.2) |
| **Items** | Auto-populated from the linked receipts; shows distribution result |

#### 4.3.2 Charge Types

| Charge Label | Distribution Method | Currency | Notes |
|---|---|---|---|
| Transportation / Freight | By quantity or by value | Typically AMD, EUR, or USD | Per-shipment cost; select distribution method based on whether items are similarly sized/valued |
| Import Duty | By value | AMD | Pre-filled from `import_tax_rate` on each item; user confirms |
| Other Fees | By quantity or by value | Any | Customs clearance fees, brokerage, port fees, etc. |

Distribution methods available:
- **By Qty** — each unit absorbs an equal share of the charge, regardless of item value.
- **By Amount (Value)** — each item absorbs a share proportional to its line total. Use this when items have significantly different prices.

#### 4.3.3 Currency and Exchange Rate

- Each charge row on the LCV has its own currency and exchange rate.
- The exchange rate is entered at LCV creation time, reflecting the rate on the day of the transaction.
- This is the authoritative rate for that shipment's cost calculation — it does not change retroactively.

#### 4.3.4 Outcome

After submitting the LCV:
- ERPNext recalculates the Valuation Rate of every item line in the linked receipt.
- New Valuation Rate = `(supplier price + distributed charges) / qty`.
- All subsequent stock movements from that batch/lot use this revised rate.
- The stock ledger records the adjustment entries.

### 4.4 Step 4 — Purchase Invoice

The Purchase Invoice is the financial payable to the supplier. It is separate from the LCV (the LCV handles landed charges; the PI handles what you owe the supplier).

Rules (from Doc 07):
- PI is created from the Purchase Receipt.
- PI amount matches what the supplier billed (not what the LCV computed).
- Any charges on the LCV that come from a separate vendor (e.g., a freight forwarder) should be invoiced separately against that vendor — they are not part of the supplier's PI.

---

## 5. Roles and Responsibilities

| Role | Responsibility |
|---|---|
| `Ops - Inventory` (Purchasing team) | Creates PO, submits Purchase Receipt, assigns batch/serial/expiry at receiving |
| `Ops - Accounting` | Creates and submits the Landed Cost Voucher; creates Purchase Invoice |
| `Ops - Directors` | Approves POs before submission (per Doc 07) |

Separation of duties note:
- The person who physically receives goods (Inventory) is distinct from the person who records the financial cost (Accounting).
- This ensures that the landed cost calculation is reviewed by the accounting function, not assumed by the warehouse.

---

## 6. Batch Tracking Policy

### 6.1 Items already batch-tracked (expiry)

These items automatically get per-lot cost isolation. No additional decision is needed. The LCV distributes costs to the exact batches received in that receipt.

### 6.2 Items not currently batch-tracked

These items use Moving Average valuation. All stock of the item blends into a single average cost. This is simpler operationally.

When to consider adding batch tracking for cost isolation:
- Large price swings between purchase lots (e.g., >10–15% price difference).
- Need to track COGS accurately by lot for regulatory or audit purposes.
- Items with long shelf life where multiple shipments overlap in stock.

When Moving Average is acceptable:
- Frequently reordered items with stable pricing.
- Low-value bulk supplies where lot-level precision doesn't justify the data entry overhead.

Decision is made per item, in the Item master. Once a batch is consumed, its tracking cannot be changed retroactively.

### 6.3 Batch naming convention

When a batch must be created at receiving:
- **Preferred**: use the supplier's printed lot number / batch code. Enables traceability to supplier in case of defects or recalls.
- **Alternative**: use an internal naming series `LOT-YYYY-#####` if the supplier does not provide lot codes.

---

## 7. Reporting Implications

If this flow is followed:

**Cost accuracy:**
- Valuation Rate in stock reports reflects actual landed cost per unit.
- COGS on sales reflects true cost of what was sold, including import charges.

**Per-lot cost visibility:**
- For batch-tracked items: Valuation Rate is visible per batch in the Stock Ledger.
- For non-tracked items: Moving Average rate is visible on the Item record.

**Import duty audit:**
- Each LCV records the import duty amount, rate source (HS code), and the exchange rate used.
- Searchable by receipt or item.

**Charge breakdown per shipment:**
- The LCV document is the permanent record of how charges were distributed. It is queryable per supplier, per date range, per item.

---

## 8. Invariants and Acceptance Criteria

- A Purchase Receipt must never be submitted for an import shipment without a follow-up LCV (unless the shipment truly has zero additional charges).
- The LCV must reference the correct Purchase Receipt(s) — not a different receipt from a different shipment.
- Import duty on the LCV must be derived from the item's `import_tax_rate` field (pre-filled, user-confirmed) — not manually entered from memory.
- Exchange rate on each LCV charge must reflect the actual rate on the day of the transaction.
- Batch numbers for batch-tracked items must be assigned at Purchase Receipt time, not retroactively.
- The Valuation Rate after LCV submission is the authoritative cost price. No separate "cost price" column is maintained manually on items.
