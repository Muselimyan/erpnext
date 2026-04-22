# Doc 07 — Suppliers and Procurement (Basic P2P) (Operational)

## 1) Purpose
This document defines the operational rules for:
- Supplier master data (who you buy from, and how you reference them)
- Basic procurement (P2P) flow:
  - Purchase Order → Purchase Receipt → Purchase Invoice
- Director approval control for purchasing
- Governance rules that keep buying, receiving, inventory valuation, and payables consistent

Non-goals:
- This doc does not provide step-by-step ERPNext configuration.
- This doc does not define the international shipment/import tracking workflow (Doc 07.1).
- This doc does not define the reorder threshold rules (Doc 08), but it defines the invariants that Doc 08 depends on.

---

## 2) Core principles
- **One item → one supplier (default rule)**
  - The catalog must not have “the same item from multiple suppliers” unless you have a formal substitution policy.

- **PO is an intention, Receipt is physical truth, Invoice is financial truth**
  - Do not treat a PO as received stock.
  - Do not treat an invoice as proof of receipt.

- **Receiving is the inventory gate**
  - Stock must enter sellable inventory only through a controlled receiving step.

- **Approvals are centralized**
  - Director team owns purchasing approvals (and escalations).

- **Every purchase must be explainable later**
  - Who requested it, who approved it, what arrived, what was invoiced, and what was paid.

---

## 3) Entities and what they represent
### 3.1 Supplier
A `Supplier` represents a legal or practical entity you buy from.

Operationally, Supplier data supports:
- Grouping reorder needs by supplier (Doc 08)
- Creating POs per supplier
- Payables and supplier performance reporting

### 3.2 Purchase Order (PO)
A PO is your internal commitment to buy a specific list of items.

Operational meaning:
- A PO is used to:
  - communicate what you intend to buy
  - request director approval
  - track what was intended vs what arrived

### 3.3 Purchase Receipt (PR)
A Purchase Receipt represents what physically arrived.

Operational meaning:
- Receipt is the moment inventory becomes your responsibility and should become visible in stock reports.

### 3.4 Purchase Invoice (PI)
A Purchase Invoice represents what the supplier billed you.

Operational meaning:
- The PI is the authoritative payable record.

---

## 4) Supplier master data rules
### 4.1 Canonical supplier identity
Rules:
- One supplier must have one canonical `Supplier` record.
- Avoid duplicates (e.g., “Medtronic GmbH” vs “Medtronic” vs “Medtronic Europe”).

If you truly buy from multiple legal entities under one brand:
- Create separate Supplier records only when it affects:
  - who you pay
  - documents received (invoice issuer)
  - or operational contacts/addresses

### 4.2 Minimum supplier fields (operational)
At minimum, a Supplier record should allow staff to answer:
- Who do we contact?
- What currency/terms do we typically buy in?
- Who approves purchases for this supplier?

Recommended data to maintain (not all must be mandatory):
- Supplier legal name
- Primary contact person(s)
- Email / phone / messaging channel
- Supplier country
- Default purchase currency
  - Current policy: mostly `USD`, sometimes `EUR`.
- Payment terms
  - Current policy: mostly prepayment (most commonly 100% in advance; sometimes partial; rarely after receipt).
- Notes (e.g., MOQ, lead times, “only order via distributor”, etc.)

---

## 5) Item ↔ Supplier invariants
These rules are foundational for reorder-by-supplier.

Rules:
- Each sellable stock item must have exactly **one** supplier (default policy).
- Each **variant** item is a real purchasable SKU and must also have its supplier set.

Exception policy (if needed later):
- If you must support alternative suppliers for the “same” real-world product, you must choose one:
  - create separate Items (one per supplier), or
  - define a formal substitution policy (not covered in this doc)

Operational reason:
- Without this rule, staff cannot reliably build a “what to order from Supplier A” list.

---

## 6) Basic procurement workflow (P2P)
This section defines the operational sequence and handoffs.

### 6.1 Trigger: “We need to buy”
Typical triggers:
- Reorder list indicates low stock (Doc 08)
- Ad-hoc demand (large client order, new product line)
- Replacement purchase (damaged/expired/write-off)

Operational rule:
- The system must always allow you to answer: **why** this PO exists.

### 6.2 Draft PO creation (Ordering team)
Rules:
- POs are created as **Draft** first.
- A PO must be per-supplier (do not mix suppliers on one PO).
- PO quantities must be realistic and aligned with packaging/UOM rules (Doc 06).

Operational intent:
- Draft PO = “proposal” that is complete enough for director approval.

### 6.3 Director approval gate
Confirmed decision:
- Purchase orders require approval by the Director team.

Operational rule:
- A PO must not be submitted/sent externally until approval is recorded.

Approval record (alignment with Doc 10 / Doc 03):
- Treat purchase approval as an explicit approval checkpoint owned by Directors.
- If you use the task system for approvals, the canonical operational signal is:
  - a Director-owned `Purchase Approval` task exists for the PO, and
  - the task is completed with an explicit approve/reject note.

Approval outcomes:
- Approved
  - PO proceeds to submission/sending.
- Rejected
  - PO is not used; the reason must be recorded.

### 6.4 Supplier communication (“Send PO”)
Operational expectation:
- The supplier must receive a clear, unambiguous order that matches the approved PO.

Rule:
- Any change after approval requires re-approval (even if small), unless you explicitly adopt a “minor edit” policy.

### 6.4.1 Prepayment (current default)
Current policy:
- Most supplier purchases are paid before goods arrive (usually 100% advance; sometimes partial; rarely after receipt).

Operational rules:
- No payment should be made against a PO that has not been approved.
- When goods arrive later, receiving must still be done based on physical reality (not based on what was paid).

### 6.5 Receiving (warehouse / inventory team)
Receiving principles:
- You receive what arrived, not what was ordered.
- Partial deliveries are normal; do not force a receipt to match the PO.

Operational rules:
- Receiving is the point where:
  - quantities become stock
  - serial/batch/expiry must be captured for tracked items (per tracking policy)

Pack-breaking note (buy boxes, sell singles):
- If an item is stocked/sold as singles but purchased in boxes, receiving must apply the correct UOM conversion so stock enters `Main - WH` accurately.
- For expiry-tracked items, prefer the single-Item + UOM-conversion model so batch/expiry stays on one Item identity.

Warehouse destination:
- Normal receiving destination is your main sellable stock location (Doc 05):
  - `Main - WH`

Exceptions:
- Current policy: no quarantine/inspection step at go-live.

### 6.6 Supplier invoice entry (Accounting)
Rules:
- Accounting creates the Purchase Invoice based on the supplier’s invoice.
- Purchase pricing must be preserved as received/billed (for later margin and audit).

Operational note:
- Receipt and invoice can arrive in either order (common in imports). The system must support that reality.

Control concept: three-way match (operational)
- The organization should be able to compare:
  - what was ordered (PO)
  - what arrived (Receipt)
  - what was billed (Invoice)
- Any mismatch must be explainable and resolved explicitly (not silently ignored).

---

## 7) Controls and governance
### 7.1 Separation of duties (alignment with Doc 03)
Rules:
- Ordering team prepares the draft PO.
- Directors approve/reject.
- Receiving team records what arrived.
- Accounting records what was billed.

Why this matters:
- It reduces the risk of “paper-only” purchases and untraceable adjustments.

### 7.2 Change control rules
Rules:
- Any approved PO edited materially must be re-approved.
- Do not delete purchasing documents; cancel with a reason.

### 7.3 Handling supplier substitutions
Because of “one item → one supplier”, substitutions must be explicit.

Operational policy recommendation:
- If the supplier ships a different product than ordered, treat it as:
  - a different Item, or
  - a rejected/returned line

Do not silently “accept as equivalent” without a defined substitution rule.

---

## 8) Common exceptions (how to handle them)
### 8.1 Partial delivery
- Receive what arrived.
- Keep the PO open for remaining quantities (unless you cancel remaining lines).

### 8.2 Over-delivery
- Receive actual quantity.
- Escalate to ordering/directors if it affects budget or shelf life.

### 8.3 Damaged goods / short shelf-life
- Do not place into sellable stock without explicit acceptance.
- Record discrepancy and escalate.

### 8.4 Supplier invoice does not match receipt
- Accounting records the supplier invoice as billed.
- Discrepancies must be resolved explicitly (credit note, correction, or approved write-off policy).

### 8.5 Returns to supplier
Current policy:
- Returns to supplier are extremely rare.

Operational rule:
- When it happens (wrong/damaged product), treat it as an exception that requires explicit director visibility and a documented resolution.

---

## 9) Reporting implications
If these rules are followed, you can reliably report:

Purchasing:
- POs created vs approved vs rejected
- Cycle time from draft → approved
- Outstanding ordered quantities (ordered but not yet received)

Supplier performance:
- Fill rate (received vs ordered)
- Lead time (order date vs receipt date)
- Discrepancy rate (short/over/damaged)

Financial:
- Purchases by supplier and period
- Purchase price history per item

Operational (inventory):
- Stock availability is trustworthy because only receipts add stock.

---

## 10) Confirmed operating assumptions (current)
- Purchase currency is mostly `USD`, sometimes `EUR`.
- Suppliers are usually paid before receipt (most commonly 100% advance; sometimes partial; rarely after receipt).
- Returns to supplier are extremely rare and treated as an exception workflow.
- No formal quarantine/inspection stage is required at go-live.

---

## 11) Acceptance criteria
- A PO never increases stock; only receiving does.
- Purchase Orders cannot be sent/submitted without an explicit director approval record.
- For batch/expiry and serial tracked items, receiving captures the required tracking data.
- Purchasing can answer “what is still expected to arrive” per supplier.
- Accounting can answer “what we owe” per supplier, and discrepancies between PO/Receipt/Invoice are handled explicitly.
