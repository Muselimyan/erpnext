# Migration Notes

Running log of post-migration cleanup tasks, known issues, and data-quality notes.
Updated after each doc implementation. Human action items are marked **[ ]**.

---

## Doc 03 — Roles, Permissions & Responsibilities

### Pending / To-Do
- **[ ]** Replace the 7 sample users (`*@example.com`) with real staff emails and secure passwords before go-live:
  - `order.team@example.com` → Ops - Order Accepting
  - `inventory.team@example.com` → Ops - Inventory
  - `returns.team@example.com` → Ops - Returns
  - `dispatch.coordinator@example.com` → Ops - Delivery
  - `driver.01@example.com` → Delivery Driver
  - `accounting.team@example.com` → Ops - Accounting
  - `director.01@example.com` → Ops - Directors
- **[ ]** Verify `server_script_enabled` remains `1` after any bench restart or Frappe upgrade (it was set directly in MariaDB).

### Notes / Known Issues
- `Task Access Policy` is a custom DocType — include it in backups before any Frappe major version upgrade.
- The Before Save script on `Task` (`Task-before-save-policy`) uses `frappe.utils.now_datetime()` instead of `import`-based calls — required by Frappe's `safe_exec` sandbox.
- All 13 Task Access Policy records created and match the `task_kind` Select field options exactly.
- Role permissions configured on: `Task`, `Sales Order`, `Stock Entry`, `Sales Invoice`, `Payment Entry`.
- User Permissions for Task Access Policy set for all 7 sample users (29 grants total).

---

## Doc 04 — Customers (Clients)

### Pending / To-Do
- **[ ]** Delete leftover test record **`Test Doctor ASCII`** (code `TEST01`) from ERPNext UI — requires admin delete access (AI agent user cannot delete).
- **[ ]** Set real `debt_threshold_amd` values for all 146 customers — currently all set to `0` (placeholder).
- **[ ]** Uncheck `Is Provisional` for clients that have been validated by Accounting/Directors.
- ~~Review potential duplicates from the original warehouse list~~ — resolved: near-duplicate `Ավetis Medlayn ԲԿ, Berd` (extra space variant) deleted from ERPNext.
- **[ ]** When adding new clients not yet in the warehouse list, continue doctor codes from **`D146`** and hospital codes from **`H002`**.

### Notes / Known Issues
- 146 Customer records created from `Clients - Inmed` warehouse names:
  - Codes `D001`–`D145` (Doctor type)
  - Code `H001` = Arabkir Medical Center (Hospital type)
- Export snapshot (`deploy/data/customers.csv`) shows only 20 records due to the export script's default page limit — all 146 are live in ERPNext.
- Customer governance script (`Customer-before-save-governance`) blocks changes to `client_code` and `is_provisional` for users without `Ops - Accounting`, `Ops - Directors`, or `System Manager` roles.
- Context fields (`hospital`, `hospital_branch`, `doctor_name`) added to both `Sales Order` and `Sales Invoice`.
- `All Customer Groups` is a group-type record and cannot be used as a customer's group — customers are assigned `Individual` (doctors) or `Commercial` (hospitals).

---

## Doc 05 — Warehouses & Stock Rules

### Pending / To-Do
- **[ ]** When adding **new** client location warehouses, follow the naming pattern:
  `<Code> — <Doctor/Hospital Name> <Hospital Short> - Inmed`
  (continue doctor codes from `D146`, hospital codes from `H002`)

### Notes / Known Issues
- All 5 core operational warehouses deployed:
  - `Main - Inmed`, `Delivery In-Transit - Inmed`, `Return Pickup In-Transit - Inmed`, `Returns - Inmed`, `Clients - Inmed` (group)
- **Client warehouse rename completed**: all 146 client warehouses renamed from bare `<Name> - Inmed` to `<Code> — <Name> - Inmed` using `frappe.rename_doc` with `force=True`. Reference snapshot: `deploy/data/warehouses_new.csv`.
- **6 invalid warehouses deleted**: `Վաճառք պահեստից`, `Հիմնական մատակարար`, `Հարությունյան Հովնան`, `Ավetis Medlayn ԲK, Berd` (near-duplicate), `Наше предприятие`, `Test Test` — none were real client locations.
- Prod warehouse count: **156 total** (10 non-client + 146 client leaf nodes).
- 4 default ERPNext warehouses (`Stores`, `Work In Progress`, `Finished Goods`, `Goods In Transit`) are present and in use — kept intentionally.
- `Stock Auth Role` set to `Ops - Inventory` — only this role can post to frozen stock periods.
- Negative stock is disabled (`allow_negative_stock = 0`).
- Valuation method: FIFO.
- `Warehouse` DocType permissions set: `Ops - Inventory` has R/W/C; all other ops roles read-only; `Delivery Driver` has no access.

---

## Doc 06 — Items, Variants & UOMs

### Pending / To-Do
- **[ ] D1 — Item Group hierarchy**: Current structure is brand-first (`ZMD → zmd screws`). Doc 06 recommends type-first (`Implants → Screws`). Requires moving all 246 items to new groups. **Awaiting decision** before acting.
- **[ ] D2 — Item naming convention**: Current names are bare spec strings (e.g. "Cortex Screw 3.5*12mm"). Doc requires `<Brand> — <Name> — <Spec>` format. Item Codes unchanged; only `item_name` would change. **Awaiting decision** before acting.
- **[ ] D3 — Batch/expiry/serial tracking flags**: All 246 items currently untracked (`has_batch_no=0`, `has_serial_no=0`). Tracking flags must be set **before** any stock transaction is posted for a given item. Decide per item; do not bulk-set without explicit confirmation.
- **[ ] Item Attribute values** — add more values to `Diameter (mm)`, `Length (mm)`, `Hole Count` etc. as new product lines are onboarded. Current values were derived from the 246 items live at migration time.
- **[ ] Item Prices** — `Standard Selling` and `Standard Buying` price lists exist but are empty (0 records). Must be populated before Sales Orders can be priced correctly.
- **[ ] Role Permissions for Item master DocTypes** — set per Doc 06A §11.5: `Item`, `Item Group`, `Item Attribute`, `UOM` — Write/Create restricted to `Ops - Inventory` and `Ops - Directors`.

### Completed (2026-05-06)
- **`pack_breaking_policy` custom field** created on `Item` DocType: Select, options "Never break packs / Pack-breakable", required, default "Never break packs". All 246 items default to "Never break packs".
- **Default warehouse** corrected: `Stock Settings.default_warehouse` updated from `Stores - Inmed` → `Main - Inmed`. All 246 item defaults updated to `Main - Inmed`. (Stale `sample_retention_warehouse = "Test Test - Inmed"` cleared; `retain_sample` flag on item `3146-60250` also cleared.)
- **Supplier links** added to all 246 items: 245 items (groups `zmd screws`, `zmd plates`, `femoral nails`, `pfna`, `tibia nails`, `zmd wire`) → `ZMD`; 1 item `3146-60250` (group `Chunli screws`) → `CHUNLI`.
- **FEFO + near-expiry server script** (`StockEntry-before-submit-fefo`) created: DocType Event / Stock Entry / Before Submit. Issues orange warnings when a non-FEFO batch is selected, or when the selected batch expires within 1 month.
- **Medical Item Attributes** created (values derived from 246 prod items):
  - `Diameter (mm)` — 14 values: 2.0, 2.4, 2.5, 2.7, 3.5, 4.0, 4.5, 4.8, 5.0, 6.5, 8, 9, 10, 11
  - `Length (mm)` — 47 values: 12 mm through 800 mm (screw + nail + wire range)
  - `Hole Count` — 11 values: 3–13
  - `Side` — Left, Right
  - `Angle (deg)` — shell only, no values yet

### Notes / Known Issues
- Prod item count at migration: **246 items** across 7 leaf groups (local `deploy/data/items.csv` contains only a 20-item sample — the full catalog is live in ERPNext only).
- Item Attributes are infrastructure for future variant templates; existing items are all standalone (individual item codes per spec) — this is correct per Doc 06 §5.2.
- The FEFO script fires on `Before Submit` of Stock Entry; it is a warning (`msgprint`) not a hard block — consistent with go-live policy.

---

## Doc 07 — Suppliers & Procurement (Basic P2P)

### Completed (2026-05-07)

**Custom Fields — Task** (3 added):
- `purchase_order` — Link → Purchase Order; links an approval task to its PO.
- `approval_outcome` — Select (Approved / Rejected); Director's decision.
- `approval_note` — Small Text; Director's written justification.

**Custom Fields — Purchase Order** (7 added, all read-only except the two required entry fields):
- `purchase_reason` — Select (Reorder / Ad-hoc demand / Replacement / Emergency); **required**.
- `requested_by` — Link → User; **required**.
- `director_approval_status` — Select (Pending / Approved / Rejected); default `Pending`; read-only.
- `director_approved_by` — Link → User; read-only.
- `director_approved_at` — Datetime; read-only.
- `director_approval_task` — Link → Task; read-only.
- `director_approval_note` — Small Text; read-only.

**Server Scripts** (6 added, all enabled):
- `Task-purchase-approval-writeback` — Task / Before Save: when a `Purchase Approval` task is completed, writes `approval_outcome` and director identity back to the linked PO.
- `Purchase Order-before-submit-director-approval` — Purchase Order / Before Submit: hard-blocks submission unless `director_approval_status = Approved`.
- `Purchase Order-validate-one-supplier` — Purchase Order / Before Save: enforces that every PO line item belongs exclusively to the PO's supplier (Doc 07 one-supplier-per-PO rule).
- `Purchase Order-before-save-clear-approval` — Purchase Order / Before Save: if a draft PO's header or lines change after approval, resets approval to `Pending`.
- `Purchase Receipt-before-submit-main-inmed-expiry` — Purchase Receipt / Before Submit: enforces all rows land in `Main - Inmed`; for batch+expiry-tracked items, requires `batch_no` with a non-null `expiry_date`.
- `Purchase Invoice-before-submit-no-update-stock` — Purchase Invoice / Before Submit: hard-blocks submission when `update_stock = 1` (receiving must go through Purchase Receipt).

### Pending / To-Do
- **[ ]** Smoke-test the full approval flow end-to-end: draft PO → blocked submit → Purchase Approval task → Director completes as Approved → PO submit succeeds.
- **[ ]** Verify re-approval trigger: edit an approved draft PO line (qty or rate) and confirm `director_approval_status` resets to `Pending`.
- **[ ]** Test Purchase Receipt destination block: attempt submit with a non-`Main - Inmed` warehouse row and confirm hard error.
- **[ ]** Test Purchase Invoice `update_stock` block: attempt submit with `Update Stock = ON` and confirm hard error.
- **[ ]** Set `purchase_reason` and `requested_by` on any existing draft Purchase Orders before users next try to save them (new required fields will block saves on existing drafts).
- **[ ]** Confirm `Task Access Policy` record named `Purchase Approval` exists (prerequisite for the Task governance script to accept `task_kind = Purchase Approval`).

### Notes / Known Issues
- Deployment script: `deploy/doc07a-deploy.ps1` — idempotent, reads credentials from `export.ps1`. Run with `-Mode Check` to verify state, `-Mode Deploy` to create/update.
- The `Purchase Order-validate-one-supplier` script is registered as `Before Save` (not `Validate`) because `Validate` is not an accepted `doctype_event` value in this ERPNext instance.
- `Main - WH` placeholder used in Doc 07 documentation maps to `Main - Inmed` in production — scripts use the production name.
- Supplier master at deployment time: **2 suppliers** (`ZMD`, `CHUNLI`). 245 items → `ZMD`, 1 item → `CHUNLI`. No new suppliers were added as part of Doc 07A.
- Production snapshot updated post-deployment: `deploy/schema/custom-fields.json` (37 records), `deploy/schema/server-scripts.json` (9 records).
