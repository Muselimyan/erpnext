# Doc 06 — Item Catalog and Variants (Operational)

## 1) Purpose
This document defines the operational rules for:
- Building a scalable Item Catalog (thousands of items, many variants)
- Choosing when to use Item Variants vs standalone items
- Unit of Measure (UOM) and pack-size rules so stock and invoices match reality
- Tracking rules per item (Serial / Batch / Expiry) aligned with recall and accountability needs

Non-goals:
- This document does not provide step-by-step ERPNext configuration.

---

## 2) Core principles
- **One real-world product = one ERPNext Item**
  - If staff can pick the wrong thing because two items look similar, the model is wrong.

- **Item identity must be stable**
  - Once an item is used in transactions, its identity must not change in a way that breaks history.

- **Variants are for humans first, reporting second**
  - Users must be able to find the correct item quickly during:
    - purchasing
    - picking
    - surgery case preparation (Doc 11/12)
    - invoicing

- **Barcode-first where possible**
  - Prefer scanning over manual search during receiving and picking.
  - The catalog must prevent “wrong variant picked” even when scanning is not available.

- **Stock UOM must match how you physically count**
  - If the warehouse counts “boxes”, do not track “pieces” (or you will drift).
  - If the warehouse counts “pieces”, do not track “boxes” without clear conversion.

- **Tracking is not optional where it matters**
  - For traceable implants/consumables: Batch + (Expiry where applicable)
  - For instruments/tools that have serials: Serial tracking

---

## 3) Item identity: Item Code vs Item Name
ERPNext has two different concepts:
- **Item Code**: the stable unique identifier (think “primary key”)
- **Item Name**: the human-friendly name shown in most screens

Operational rules:
- Treat **Item Code as stable**.
  - Do not change Item Code casually.
- Item Name may evolve slightly (spelling cleanup), but must remain recognizable.

Recommended strategy (aligned with Doc 02 item naming):
- Use Item Name pattern:
  - `<Brand> — <Item Name> — <Key Spec>`

Examples:
- `Stryker — Bone Screw — 3.5mm`
- `Medtronic — Drill Bit — 2.0mm`

Rule:
- The distinguishing attribute must be present either:
  - in the Item Name, or
  - as Variant Attributes (and visible in search/list views).

---

## 4) Item Groups (category structure)
Item Groups are your primary “catalog navigation” structure.

### 4.1 What Item Groups must support
Item Groups should support:
- Fast browsing when users don’t know the exact item name
- High-level reporting (sales by category)
- Operational filtering (e.g., “implants vs instruments”)

Item Groups should NOT be used to represent:
- Supplier grouping
  - You already have one supplier per item; supplier-based buying views should filter by supplier, not by category.

### 4.2 Recommended top-level Item Group structure (scalable)
Keep the top level small and stable.

Recommended baseline:
- `Implants`
- `Instruments / Tools`
- `Consumables / Disposables`
- `Accessories / Parts`
- `Services / Non-Stock` (only if you invoice services)

Then subdivide by specialty and product family where it helps picking and reporting.

Operational rule:
- A user should reach the correct family in 2–4 clicks.

---

## 5) Variants strategy (the most important part)
Your catalog contains many products where the only difference is a measurable attribute (size, length, angle).

### 5.1 When to use Item Variants
Use Item Variants when:
- You have a product family with many sizes/lengths
- The variants share:
  - the same “base” description
  - the same operational handling rules
  - the same supplier pattern (still one supplier per variant)

Example families:
- Screws (diameter × length)
- Plates (shape × length)
- Nails (diameter × length)
- Drill bits (diameter)

This matches the surgery-set requirement (Doc 11):
- Doctors request “only sizes X/Y/Z”, and selecting a size must mean selecting a specific variant item.

### 5.2 When NOT to use variants
Avoid variants when:
- The “variants” differ in meaningful operational behavior:
  - different supplier
  - different regulatory handling
  - different storage conditions
  - different tracking rules
- The attribute list becomes unbounded free text (then it’s not a controlled variant system).

In these cases, create standalone items.

### 5.3 Variant attributes: design rules
Variant attributes must be:
- **Human**: match what your staff naturally says (size, length, angle)
- **Finite**: options are controlled lists, not free typing
- **Unit-consistent**: always use the same unit (e.g., mm)
- **Non-redundant**: don’t encode the same thing in multiple places

Naming rule:
- If you rely on attributes to distinguish items, make sure search results still show enough detail to prevent picking mistakes.

---

## 6) UOM and pack-size rules
This section prevents the most common inventory mistakes: counting one thing and recording another.

### 6.1 Choose a Stock UOM policy
Stock UOM should be the unit you physically count and pick.

Recommended baseline policy:
- Stock UOM = **smallest unit you will actually track without breaking**.

Examples:
- Implants sold individually (sterile pack): Stock UOM = `Nos` (piece)
- Gloves sold by the box and never split: Stock UOM = `Box`

Operational rule:
- If the warehouse sometimes breaks a box into pieces, you must explicitly decide:
  - either you will track pieces (and receiving must convert boxes → pieces), or
  - you will never break boxes (and sales must follow boxes).
  - “Sometimes” is not a stable policy: if you break packs for an item, define and document that item as pack-breakable and treat it as a standard process.

### 6.2 Purchase vs Sales UOM consistency
Rules:
- Every item must have a clear “how we buy it” and “how we sell it” reality.
- If you buy in boxes but sell in pieces, conversion must be well-defined and enforced.

Decision (important):
- If the item is batch/expiry-tracked, avoid modeling “Box” and “Single” as separate Items.
  - Use one Item with:
    - Stock UOM = single unit (`Nos`)
    - Purchase UOM = `Box`
    - a conversion factor (`1 Box = N Nos`)
  - This keeps batch/expiry traceability on one Item identity.

Allowed exception:
- If the item is not batch/expiry-tracked, you may keep separate Items:
  - one Item representing the box
  - one Item representing the single unit
  - and you must use a controlled repack/conversion stock movement so inventory stays accurate.

### 6.3 Integer quantities rule
Operational rule:
- Prefer UOMs where quantities are whole numbers during daily operations.
- Decimal quantities increase mistakes for pick/pack and reconciliation.

---

## 7) Tracking rules per item (Serial / Batch / Expiry)
This is aligned with your confirmed policy:
- **Implants / consumables**: Batch + Expiry where applicable
- **Tools / instruments**: Serial where the instrument has a serial

### 7.1 Batch + expiry (implants/consumables)
Operational meaning:
- When you receive these items, the lot/batch and expiry (when applicable) must be captured.
- When you dispatch/return/consume these items (especially for surgery cases), the correct batch must be recorded.

FEFO rule (critical):
- For expiry-tracked items, batch selection must follow **FEFO** (First-Expiry-First-Out): use the batch with the earliest expiry first.
- If a user selects a “fresher” batch while an older-expiring batch is available in `Main - WH`, the system must alert.

Business outcomes:
- Recall reporting by consumed batch (Doc 11)
- Expiry risk control

Decisions:
- FEFO enforcement is a **warning** at go-live (not a hard-block).
- Near-expiry threshold for warnings/escalation is **1 month**.

### 7.2 Serial (tools/instruments)
Operational meaning:
- Each physical tool with a serial is tracked as one serial number.
- The stock ledger becomes the source of truth for which serial is at which client location or in transit.

Business outcomes:
- Tool accountability per client location
- Missing/damaged detection in surgery workflow (Doc 12)

### 7.3 Items with no tracking
Operational rule:
- If an item has neither batch nor serial tracking, you must still ensure:
  - correct item selection
  - correct UOM
  - correct quantities

---

## 8) Supplier rule (one supplier per item)
Confirmed requirement:
- Each item has exactly one supplier.

Operational meaning:
- Reorder lists and PO preparation can group/filter items by supplier.
- If the same “type of product” exists from a different supplier, treat it as a separate item identity unless you have a formal substitution policy.

---

## 9) Governance: who can create/change items
Item master data is high-impact.

Rules:
- Only designated staff should create new items and variants.
- Changes must be controlled:
  - name/spec changes can affect picking
  - UOM changes can invalidate stock history
  - tracking flags (batch/serial) must not be flipped casually

Operational safeguard:
- Prefer “disable/deprecate” over deletion.

---

## 10) Reporting implications
If Doc 06 rules are followed, reporting becomes reliable:

Inventory reporting:
- Stock by category (Item Group)
- Stock by tracking dimension:
  - batch + expiry (for implants/consumables)
  - serial location (for tools)

Sales reporting:
- Sales by Item
- Sales by Variant (sizes/lengths)

Buying / reorder reporting:
- Low-stock items grouped/filterable by supplier

Surgery-set reporting:
- Set templates can safely reference exact variant items
- Recall-by-consumed batch is possible (Doc 11)

---

## 11) Current decisions and remaining clarifications
Packaging / pack-breaking:
- Pack-breaking happens sometimes.
- For accuracy, pack-breaking must be defined per item/category (either “never break” or “pack-breakable with a controlled conversion policy”).
- Remaining clarification: which categories/items are pack-breakable in real life (tracked in `open-questions.md`).

Additional clarification (recommended):
- For pack-breakable items that require batch/expiry traceability, prefer the single-Item + UOM-conversion model.

Barcode usage:
- Use as much barcode scanning as possible (receiving and picking).

Item Code strategy:
- You have an existing item code/SKU system.
- Default operational rule: keep Item Codes stable and compatible with your existing SKUs at go-live.
- If you later change the coding scheme, keep an explicit reference to the old code so history remains searchable.

---

## 12) Acceptance criteria
- Users can find the correct item variant quickly (low mistake rate).
- Item Group structure is stable and supports browsing.
- Stock UOM matches how the warehouse counts.
- Traceable items are configured so recall and accountability reporting is possible.
- Reorder reporting can be filtered/grouped by supplier.
