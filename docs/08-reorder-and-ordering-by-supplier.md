# Doc 08 — Reorder System (Low Stock → PO per Supplier) (Operational)

## 1) Purpose
This document defines the operational rules for an “always-available reorder list” that:
- shows what is low (and why)
- can be grouped / filtered by supplier
- converts into a controlled purchasing action (Doc 07)

Goals:
- Prevent stockouts for high-importance items
- Reduce overstock (cash tied up) and expiry risk
- Make purchasing decisions explainable (auditable)

Non-goals:
- This doc does not provide ERPNext configuration steps.
- This doc does not define the international shipment/import tracking pipeline (Doc 07.1).

---

## 2) Dependencies (what Doc 08 assumes)
Doc 08 depends on these already-decided rules:
- Item and variant structure is correct (Doc 06).
- Each item has exactly one supplier (Doc 06 / Doc 07).
- Purchasing flow is PO → Receipt → Invoice, with director PO approval (Doc 07).
- Warehouses represent physical responsibility (Doc 05).
  - Sellable stock is primarily in `Main - WH`.
  - Client location warehouses represent company-owned stock at client locations (surgery cases and permanent on-site sets).

---

## 3) Core principles
- **The reorder list is a decision support tool, not autopilot**
  - It proposes what to buy; humans approve what actually gets ordered.

- **Low stock must be visible at all times (no fixed cycle required)**
  - A buyer should be able to open the list any day and see what needs attention.

- **A reorder signal must be explainable**
  - For each item: “what is the current available quantity?”, “what is the threshold?”, “what demand is coming?”, “what supply is already on the way?”.

- **Reorder is only meaningful if item master data is correct**
  - Wrong UOM, wrong supplier assignment, or wrong variant structure will produce wrong reorder decisions.

- **Do not confuse ‘company-owned somewhere’ with ‘sellable now’**
  - Stock at hospitals pending return and stock in `Returns - WH` may be company-owned but may not be available for immediate sale.

---

## 4) What “low stock” means (definitions)
To keep everyone aligned, use these concepts consistently:

- **Sellable on-hand**
  - What is physically in `Main - WH` and can be picked today.

- **Committed demand**
  - Quantities you have promised or effectively reserved for near-future operations.
  - Examples:
    - open sales orders not yet delivered
    - surgery cases being prepared / dispatched (depending on your workflow)

- **Expected inbound supply**
  - Quantities that are already ordered and reasonably expected to arrive.
  - In basic P2P terms (Doc 07): approved POs that are still open.

- **Non-sellable / uncertain stock**
  - Company-owned quantities that are not guaranteed sellable today:
    - `Clients - WH` (company-owned at-client stock: pending return / usage reconciliation, and permanent on-site sets)
    - `Return Pickup In-Transit - WH`
    - `Returns - WH`

Operational rule:
- The reorder list must primarily protect the ability to ship from `Main - WH`.
- Non-sellable / uncertain stock should be shown as informational, but should not be counted as available for reorder calculations.

---

## 5) Reorder thresholds: the operational policy
Doc 08 assumes a per-item threshold model.

### 5.1 Threshold types (choose per category, refine per item)
There are two common threshold styles; both are valid.

1) **Reorder Point (ROP) + Reorder Quantity**
- Trigger: when net availability drops below ROP
- Action: order a suggested quantity

2) **Min / Max**
- Trigger: when net availability drops below Min
- Action: order up to Max

Operational recommendation (small assumption):
- Use **Min/Max** for fast-moving consumables.
- Use **ROP** for implants / specialized items where you want more control.

Operational rule:
- Threshold style may be standardized per category, but the actual threshold values may vary per item and even per variant (based on real consumption and lead time).

### 5.2 What thresholds must cover
A good threshold covers:
- supplier lead time variability
- demand variability
- buffer for urgent cases

Operational rule:
- Thresholds are not permanent.
  - Review them periodically based on actual usage and supplier performance.

---

## 6) How to compute “what to order” (operational logic)
This section defines the logic without prescribing exact ERPNext fields.

### 6.1 Net availability (concept)
Reorder decisions should be based on **net availability**, not raw on-hand.

Conceptually:
- `Net available today` = `Sellable on-hand in Main - WH` − `Committed demand`

If you use an inbound-aware view:
- `Net available with inbound` = `Net available today` + `Expected inbound supply`

Operational rule:
- For critical items, do not rely on “hope” inbound.
  - If the supply risk is high, order earlier.

### 6.2 Suggested order quantity
Operationally, a suggested order quantity should aim to:
- restore coverage for the next lead-time window
- avoid over-buying slow movers

Current target coverage window (confirmed baseline):
- Fast movers: target about 1 month coverage.
- Imports / longer lead time suppliers: target about 2–3 months coverage.

Examples of practical policies:
- If Min/Max:
  - suggested = Max − net available
- If ROP + reorder quantity:
  - suggested = fixed reorder quantity (or a coverage-based quantity)

---

## 7) Variants and reorder (important)
Rule:
- Reorder thresholds are defined on the **actual purchasable item**.
  - For variant families, that means thresholds live on each **variant item**, not on the template.

Operational implication:
- A single variant going out-of-stock can block a surgery case even if other sizes are available.

Recommendation (small assumption):
- For size/length families, define at least a minimum safety threshold for the most-used variants.

---

## 8) Supplier grouping and “one item → one supplier”
Because each item has exactly one supplier:
- the reorder list can always group items by supplier
- buyers can prepare **one PO per supplier** (Doc 07)

Operational rules:
- Do not mix suppliers on one PO.
- If a product is re-sourced to a different supplier, treat that as a controlled master-data change (often a new item).

---

## 9) Daily/weekly operating procedure (buyer workflow)
This defines the human operating rhythm (no fixed ordering cycle is required).

### 9.1 Daily quick check (10–20 minutes)
Recommended focus:
- critical fast movers
- items required for surgery sets
- anything already flagged as “below threshold”

Outcome:
- identify which suppliers likely need a PO today

### 9.2 Weekly deep review (30–90 minutes)
Recommended focus:
- slow movers that drift below thresholds
- unusually high consumption patterns
- supplier lead time issues

Outcome:
- adjust thresholds (governance-controlled)
- prepare planned POs for the week

---

## 10) Governance and controls
### 10.1 Who can change reorder thresholds
Thresholds drive cash and service level.

Rules:
- Threshold changes are owned by Purchasing Leads.
- Threshold changes should be traceable (who/when/why).

### 10.2 Director approval linkage
Doc 07 requires director approval for POs.

Operational rule:
- The reorder list may suggest POs, but the PO is not considered “real” until director approval.

### 10.3 Expiry-aware buying (for batch/expiry items)
For implants/consumables with expiry tracking:
- “Enough quantity” is not enough if it expires soon.

Operational rule:
- Buyers must consider:
  - quantities expiring within the lead-time + usage window
  - and avoid over-buying that increases expiry write-off risk

---

## 11) Exception handling
### 11.1 Emergency orders
When a critical item is needed urgently:
- buyers may create an emergency PO
- directors still approve (unless you explicitly define an emergency override policy)

Operational safeguard:
- emergency decisions must be explainable later (who requested, why urgent).

### 11.2 Stock is “somewhere else” (hospitals / returns / in-transit)
Operational rule:
- Do not treat hospital/returns/in-transit stock as available for normal sales.

However, if you have an urgent need:
- you may choose to pull back stock operationally, but it must be explicit and traceable.

### 11.3 Substitutions
Given “one item → one supplier”, substitutions are exceptions.

Operational rule:
- If an alternative product is ordered, it should be represented explicitly (often as a different item).

---

## 12) Reporting implications
If Doc 08 rules are followed, you can report:

Purchasing operations:
- items below threshold (by supplier)
- “days below threshold” (how long an item stayed critical)
- reorder accuracy (how often urgent orders happened)

Supplier readiness:
- lead time patterns (once you start measuring)
- fill rate / partial delivery frequency (ties into Doc 07)

Inventory health:
- stockouts by item/variant
- overstock + slow movers
- expiry risk buckets for expiry-tracked items

---

## 13) Confirmed operating assumptions (current)
- Coverage window target:
  - fast movers: about 1 month
  - imports / longer lead times: about 2–3 months
- Hospital/returns/in-transit stock is not counted as “available” for reorder math (informational only).
- Reorder threshold changes are owned by Purchasing Leads.
- Thresholds can vary by category and can be refined per item/variant.

---

## 14) Acceptance criteria
- At any time, purchasing can open a list of low-stock items.
- The list can be grouped/filtered by supplier.
- Suggested POs can be built per supplier, and directors can approve before submission.
- The system supports accurate ordering for high-variant product families.
- Reorder decisions are explainable in hindsight (auditability).
