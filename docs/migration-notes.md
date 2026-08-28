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

---

## Doc 08 — Reorder System (Low Stock → PO per Supplier)

### Completed (2026-05-07)

**Roles** (2 new custom roles):
- `Ops - Purchasing` — buyers who create POs; Read-only access to Item master.
- `Ops - Purchasing Lead` — owns reorder thresholds; Read+Write access to Item master.

**Custom Field — Item** (1 added):
- `reorder_change_reason` — Small Text; required by governance script when reorder rows change.

**Server Script** (1 added, enabled):
- `Item-before-save-reorder-governance` — Item / Before Save: if `reorder_levels` rows change vs the saved state and `reorder_change_reason` is blank, throws a hard error. Enforces Doc 08 §7 traceability rule.

**Item Role Permissions** (2 Custom DocPerm records created):
- `Ops - Purchasing` on `Item`: Read = 1, Write = 0 (perm id: `rs46v2iuml`).
- `Ops - Purchasing Lead` on `Item`: Read = 1, Write = 1 (perm id: `rs7iid2a2s`).

### Pending / To-Do
- **[ ]** Assign real staff users to `Ops - Purchasing` and `Ops - Purchasing Lead` roles before go-live.
- **[ ]** Set reorder thresholds on items that need reorder management (Item master → Reorder section):
  - Warehouse must always be `Main - Inmed`.
  - Fast-moving consumables: Min/Max style (Reorder Level = Min, Reorder Qty = Max − Min).
  - Implants / specialized items: ROP style (Reorder Level = ROP, Reorder Qty = fixed coverage qty).
  - Coverage targets: fast movers ~1 month, imports/long lead-time ~2–3 months.
  - Requires `Reorder Change Reason` field filled on each save (governance script is live).
- **[ ]** Create saved report **`Stock Balance — Main - Inmed`**: open `Stock Balance` report → filter Warehouse = `Main - Inmed` → save.
- **[ ]** Create saved list view **`Items — Active Stock`**: open `Item` list → filter Disabled = No, Is Stock Item = Yes → add columns (Item Code, Item Name, Item Group, Default Supplier) → save.
- **[ ]** Navigate to `Stock Reorder` tool → filter Warehouse = `Main - Inmed` → save view as **`Reorder — Main - Inmed`** (if the page supports saving).
- **[ ]** Validate governance: confirm a non-lead user cannot save Item with changed reorder rows, and a Lead user is blocked without `Reorder Change Reason`.

### Notes / Known Issues
- Deployment script: `deploy/doc08a-deploy.ps1` — idempotent, `-Mode Check` / `-Mode Deploy`. Custom DocPerm records show `exists: false` in Check verification output (list-API limitation for `Custom DocPerm` DocType) — the records exist in prod; verify via Role Permission Manager → Item.
- `Item-reorder_change_reason` and `Ops - Purchasing Lead` were already present in prod before this deployment (created externally) — both were updated/re-confirmed by the script.
- Reorder governance script uses `reorder_levels` as the Item Reorder child table fieldname (standard ERPNext). If fieldname differs in this instance, update `REORDER_FIELDNAME` in the script.
- `Ops - Inventory` item write permissions are **unchanged** — that is a separate open item tracked under Doc 06 pending D1/D2.
- `purchase_reason` on Purchase Order already includes `Reorder (Doc 08)` as first option (deployed in Doc 07A).
- **2026-05-08 cleanup**: A second deployment pass (unaware of the 2026-05-07 deployment) created two duplicate artifacts — `Item-before-save-reorder-change-reason` server script (370 chars, weaker logic) and Custom DocPerm `j08rtbhkr0` (Ops - Purchasing Lead, Read+Write). Both were cleaned up: the duplicate script was disabled (`disabled=1`), the duplicate DocPerm was deleted. Canonical artifacts are `Item-before-save-reorder-governance` and `rs7iid2a2s`.

---

## Doc 09A — Standard Selling Flow (No Return Expected)

### Completed (2026-05-07)

**Custom Fields — Sales Order** (7 added):
- `is_prepaid` — Check; flags order as prepaid (payment required before dispatch).
- `prepayment_required_amount_amd` — Currency; minimum prepayment amount (shown only when `is_prepaid = 1`).
- `prepayment_payment_entry` — Link → Payment Entry; the prepayment record.
- `discount_approval_status` — Select (Not Required / Pending / Approved / Rejected); set by server script, read-only.
- `discount_approval_task` — Link → Task; pointer to the open Discount Approval task; read-only.
- `discount_approval_note` — Small Text; director's note when approving/rejecting; read-only.
- `manual_pricing_reason` — Small Text; required when any line rate differs from price-list-derived rate.

**Custom Fields — Task** (7 added):
- `sales_order` — Link → Sales Order; used by Delivery and Discount Approval tasks.
- `customer` — Link → Customer; used by Debt Collection, Distribute Payment, and Discount Approval tasks.
- ~~`warehouse_pickup_photo`~~ — **REMOVED** (Doc 18: photos now use File records; gate uses `task_has_image()`)
- ~~`warehouse_dropoff_photo`~~ — **REMOVED** (Doc 18: photos now use File records; gate uses `task_has_image()`)
- `payment_entry` — Link → Payment Entry; used by Distribute Payment tasks.
- `current_debt_amd` — Currency; populated by debt scheduler on Debt Collection tasks.
- `debt_threshold_amd` — Currency; snapshot of the threshold at time of debt escalation.

**Custom Field — Stock Entry** (1 added):
- `sales_order` — Link → Sales Order; ties dispatch staging entries to a Sales Order.

**Server Scripts** (8 added, all enabled):
- `Sales Order-before-save-discount-approval` — SO / Before Save: detects per-line discounts and manual rate overrides; creates/cancels Discount Approval tasks; enforces Accounting/Directors-only manual pricing; preserves approval state when discount terms are unchanged.
- `Task-before-save-discount-approval-writeback` — Task / Before Save: when a Discount Approval task is completed, writes `discount_approval_status` + `discount_approval_note` back to the linked Sales Order via `frappe.db.set_value` (SO is submitted at this point; `.save()` would be blocked).
- `Stock Entry-before-submit-dispatch-gate` — Stock Entry / Before Submit: for `Main → Delivery In-Transit - Inmed` transfers, enforces: (1) Sales Order link required, (2) discount not Pending/Rejected, (3) Delivery Task with Warehouse Pickup Photo exists, (4) prepaid gate if `is_prepaid = 1`.
- `Stock Entry-before-save-no-client-wh` — Stock Entry / Before Save: blocks any Stock Entry linked to a Sales Order from staging into any warehouse under `Clients - Inmed`.
- `Delivery Note-before-submit-delivery-gate` — Delivery Note / Before Submit: enforces all rows issue from `Delivery In-Transit - Inmed`; re-checks discount and prepaid gates for each linked Sales Order.
- ~~`Task-before-save-return-dropoff-photo`~~ — **DISABLED** (replaced by `task_has_image()` in dispatch gates; see Doc 18).
- `Scheduled-debt-collection` — Scheduler Event / Hourly: scans all Customers with a `debt_threshold_amd > 0`; for any whose GL net-receivable exceeds the threshold, creates or updates a Debt Collection task assigned to the first active director.
- `Payment Entry-after-submit-distribute-payment` — Payment Entry / After Submit: for Receive payments from Customers, creates a Distribute Payment task assigned to the first active director (idempotent — skips if an open task already exists for the same PE).

### Pending / To-Do
- **[ ]** Configure Role Permissions (manual — Role Permission Manager) for: `Sales Order` (Ops - Order Accepting: RWC+Submit+Cancel; Ops - Accounting: R; Ops - Directors: R+Cancel), `Stock Entry` / `Delivery Note` (Ops - Inventory, Ops - Delivery: RWCS; Delivery Driver: no access), `Sales Invoice` / `Payment Entry` (Ops - Accounting: RWCS).
- **[ ]** Assign real staff to roles: `Ops - Order Accepting`, `Ops - Inventory`, `Ops - Delivery`, `Ops - Accounting`, `Ops - Directors`, `Delivery Driver`.
- **[ ]** Create `Standard Selling` Price List (Selling = ON, Currency = AMD) and populate base Item Prices.
- **[ ]** Create saved view `Price Overrides — by Client` in Item Price list (filter: Price List = Standard Selling, Customer not blank; columns: Customer, Item Code, Item Name, Rate).
- **[ ]** Confirm these Task Access Policy records exist (required by server scripts): `Discount Approval`, `Debt Collection`, `Distribute Payment`, `Delivery`, `Return drop-off at warehouse`.
- **[ ]** Confirm these Task Kind values exist on the `Task-task_kind` field options: `Discount Approval`, `Debt Collection`, `Distribute Payment`, `Delivery`, `Return drop-off at warehouse`, `Returns processing / verification`.
- **[ ]** Smoke-test discount approval flow: create SO with line discount → Pending task created → director completes Approved → `discount_approval_status` = Approved → dispatch staging unblocked.
- **[ ]** Smoke-test dispatch gate: attempt Stock Entry submit (Main → Transit) without Sales Order link → blocked; without Pickup Photo → blocked.
- **[ ]** Smoke-test Delivery Note gate: attempt DN submit with wrong source warehouse → blocked.
- **[ ]** Smoke-test prepaid gate: flag SO as prepaid, attempt dispatch without submitted PE → blocked.
- **[ ]** Smoke-test debt scheduler: set a low `debt_threshold_amd` on a Customer with outstanding invoices → run hourly job manually or wait → Debt Collection task appears.

### Notes / Known Issues
- Deployment script: `deploy/doc09a-deploy.ps1` — idempotent, `-Mode Check` / `-Mode Deploy`.
- **PowerShell 5.1 encoding fix applied**: `Invoke-RestMethod` now sends body as explicit `UTF8.GetBytes()` to avoid Windows-1252 encoding of non-ASCII characters (EM DASH U+2014 in f-strings). Without this, scripts containing `—` were rejected with HTTP 417 `DataError: Invalid request body`.
- **Top-level `return` not allowed in server scripts**: Frappe's `validate_script()` uses `compile_restricted()` which fails on `return` outside a function. All scripts use nested `if` blocks to match the pattern of existing working scripts (`Task-purchase-approval-writeback`).
- `Task-before-save-discount-approval-writeback` uses `frappe.db.set_value()` (not `so.save()`) because the Sales Order is submitted when the director completes the task — `Document.save()` on a submitted doc raises `ValidationError` regardless of `ignore_permissions`.
- `Delivery Note-before-submit-delivery-gate` blocks ALL Delivery Notes whose rows don't issue from `Delivery In-Transit - Inmed`. This is intentional for this system (all deliveries use the standard two-step staging flow).
- `Stock Entry-before-save-no-client-wh` only enforces when `sales_order` is set on the Stock Entry (to avoid blocking non-sales movements).
- Warehouse name placeholders in Doc 09 documentation (`Main - WH`, `Delivery In-Transit - WH`, `Clients - WH`) map to production names `Main - Inmed`, `Delivery In-Transit - Inmed`, `Clients - Inmed` — all scripts use the production names.

---

## Doc 10A — Task System Foundations + Doc 10.1A Directors Task Dashboard

### Completed (2026-05-07)

**Role** (1 new):
- `Directors TV` — read-only role for the TV wallboard user.

**Custom Fields — Task** (3 new, all optional):
- `dispatch_group_id` — Data; "Dispatch Group ID"; groups multiple docs in one trip.
- `sales_invoice` — Link → Sales Invoice; used by invoice prep tasks.
- `driver_handover_note` — Small Text; free-form handover note written by the driver.

**`task_kind` Select options updated** — added missing kind:
- `Return to warehouse (aborted delivery / cancelled order)` (position: after Delivery, before Pickup Returns)

**`Task Access Policy` records** (14 total; 13 pre-existing, 1 new):
- New record added: `Return to warehouse (aborted delivery / cancelled order)`.
- All 14 records now present: Order entry, Pack / prepare items, Dispatch picking / hand-off, Delivery, Return to warehouse (aborted delivery / cancelled order), Pickup Returns, Return drop-off at warehouse, Returns processing / verification, Invoice preparation / create invoice, Debt Collection, Distribute Payment, Discount Approval, Purchase Approval, Write-off Approval.

**Server Script — `Task-before-save-policy` (updated):** Replaced the partial governance script with the comprehensive Doc 10A version. Now enforces:
1. Auto-fill `task_access_policy` from `task_kind` (existing behaviour, kept).
2. Validate that the `Task Access Policy` record exists.
3. **Edit enforcement**: only the owning team may edit a Task (Directors / System Manager bypass).
4. **Completion enforcement**: only the owning team may mark a Task Completed (Directors / System Manager bypass).
5. **Mandatory photos**: Pack → at least one image File; Pickup Returns → at least one image File (checked by `task_has_image()`; see Doc 18). Delivery tasks no longer require photos.
6. **Single-owner rule**: Tasks in status other than Open/Cancelled must have exactly 1 assignee, and that assignee must belong to the owning team.
7. **`completed_at` timestamp**: stamped on first transition to Completed.

**Server Script — `Task-before-save-return-dropoff-photo` (disabled):** Superseded by the updated governance script above. Disabled (not deleted) to preserve audit trail.

### Pending / To-Do
- **[ ]** Create `director.tv@internal` (or similar) User, assign `Directors TV` role, set a strong password — for use on the TV wallboard.
- **[ ]** Configure `Apply User Permissions` on Task for `Directors TV` role (Role Permission Manager → Task → Directors TV → enable Apply User Permissions), then create User Permissions granting the TV user access to the specific Task Access Policies it should see.
- **[ ]** Create saved Task list views for wallboard (Option A, Doc 10.1A section 6.3): `Directors — All Open Tasks`, `Delivery — Open Tasks`, `Inventory — Open Tasks`, `Accounting — Open Tasks`, `Directors — Open Tasks`.
- **[ ]** Create Directors Workspace (Option B, Doc 10.1A section 7): Workspace named `Directors — Operations` with shortcuts to the above saved views.
- **[ ]** Assign real staff to operational roles so single-owner / team-ownership enforcement works: `Ops - Order Accepting`, `Ops - Inventory`, `Ops - Returns`, `Ops - Delivery`, `Ops - Accounting`, `Ops - Directors`, `Delivery Driver`.
- **[ ]** Review any existing Tasks in status `Working` / `Completed` that have 0 or 2+ assignees — clean them up before go-live, as the governance script will reject saves on those tasks.
- ~~**[ ]** `Surgery Case` link field on Task~~ — **DELETED 2026-08-28**: Surgery Case system removed entirely.

### Notes / Known Issues
- Deployment script: `deploy/doc10a-deploy.ps1` — idempotent, `-Mode Check` / `-Mode Deploy`.
- `Task Access Policy` DocType and 13 of 14 records were already present (created as part of doc07a context); only the new `Return to warehouse (aborted delivery / cancelled order)` record was missing.
- The governance script uses `json.loads()` (for reading `_assign` field) and `now_datetime()` — both available as globals in Frappe safe_exec. No `import` statements needed.
- **Breaking change note**: the new governance script now enforces owning-team edit rights and single-owner rule. Existing tasks with wrong team or 0/2+ assignees will fail to save until cleaned up. Directors and System Manager bypass the owning-team check, so they can fix any stuck tasks.
- `Task-before-save-return-dropoff-photo` is **disabled** (not deleted); it remains in the schema for audit purposes. The governance script fully covers its behaviour (return drop-off photo + Delivery photo + completed_at for all tasks).

---

## Doc 11A — Surgery Set Setup

### Completed (2026-05-07)

**Warehouses** (all 5 verified present — no creation needed, set up in Doc 05A):
- `Main - Inmed` (leaf, is_group=0)
- `Delivery In-Transit - Inmed` (leaf, is_group=0)
- `Clients - Inmed` (group, is_group=1)
- `Return Pickup In-Transit - Inmed` (leaf, is_group=0)
- `Returns - Inmed` (leaf, is_group=0)

**DocType — `Collection Set Item`** (child table, custom):
- Fields: `item` (Link→Item, reqd), `default_qty` (Float, reqd), `uom` (Link→UOM), `group` (Select: Tools/Instruments, Screws, Nails, Plates), `return_behavior` (Select: Expected Return/May Be Used), `is_optional` (Check), `is_critical` (Check), `notes` (Small Text)
- `istable = 1`; module = Custom

**DocType — `Collection Set`** (parent, custom, autoname by `set_name`):
- Fields: `set_name` (Data, reqd+unique), `set_code` (Data), `is_active` (Check, default 1), `notes` (Small Text), `readiness_status` (Select read-only: Ready/Short/Critical Short), `readiness_note` (Small Text read-only), `items` (Table → Collection Set Item)
- Permissions: `Ops - Inventory` (Read/Write/Create), `Ops - Directors` (Read/Write/Create), `Ops - Delivery` (Read)

**Server Script — `Surgery-Set-Type-validate-readiness`** (DocType Event: Before Save on Collection Set):
- Loops over each item row; queries `Bin` for projected stock in `Main - Inmed`.
- Sets `readiness_status = "Critical Short"` if any `is_critical` item is short.
- Sets `readiness_status = "Short"` if any non-critical item is short.
- Sets `readiness_status = "Ready"` when all items are fully coverable.
- Shows a `frappe.msgprint` warning popup listing all shortage lines.
- Warning-only — does NOT block saving.

### ~~Pending / To-Do~~ OBSOLETE (deleted 2026-08-28)
- **[ ]** Configure Item masters: serial number tracking ON for tools where individual instruments have unique identity; batch number tracking ON for implants/consumables; expiry date on batches for expiry-tracked items (FEFO).
- ~~**[ ]** Create real `Collection Set` records~~ — **DELETED**: Collection Set DocType removed
- ~~**[ ]** Verify `Ops - Inventory` and `Ops - Delivery` roles~~ — N/A for Collection Set
- ~~**[ ]** `Surgery Case` DocType~~ — **DELETED**: Surgery Case DocType removed
- ~~**[ ]** `Task-surgery_case` field on Task~~ — **DELETED**: Custom field removed

### Notes / Known Issues
- Deployment script: `deploy/doc11a-deploy.ps1` — idempotent, `-Mode Check` / `-Mode Deploy`.
- **`istable` vs `is_child_table`**: Frappe's REST API uses the internal field name `istable = 1` for child tables. The GUI label "Is Child Table" maps to the `istable` column. Using `is_child_table` in the POST body is silently ignored and the DocType is created as a regular (non-child) table — blocked the first deploy attempt.
- **`"Validate"` event removed**: This Frappe version does not accept `"Validate"` as a valid `doctype_event` for Server Scripts. The correct event is `"Before Save"` (runs after built-in validation, before the database write — equivalent behaviour for field-stamping scripts).
- The `Collection Set Item` child table was initially created without `istable = 1` (wrong field name). The deploy script detects this and auto-fixes it via a PUT with `{ istable: 1 }` on the subsequent run.
- The readiness script uses `frappe.db.get_value("Bin", ...)` to check projected stock — no `import frappe` needed (global in safe_exec).

---

## Doc 12A — Surgery Case Operational Workflow

**Deployed:** `deploy/doc12a-deploy.ps1` — idempotent, `-Mode Check` / `-Mode Deploy`.

### What Was Deployed

**DocType — `Surgery Case Item`** (child table, custom, `istable=1`):
- Fields: `item` (Link→Item, reqd), `dispatched_qty` (Float, reqd), `returned_qty` (Float, default 0), `lost_damaged_qty` (Float, default 0), `used_qty` (Float, read-only)

**DocType — `Surgery Case Serial Exception`** (child table, custom, `istable=1`):
- Fields: `item` (Link→Item, reqd), `serial_no` (Data, reqd), `exception_type` (Select: Missing/Damaged/Not Serialized, reqd), `notes` (Small Text)

**DocType — `Surgery Case`** (parent, custom, autoname: `SC-.YYYY.-.#####`):
- 26 fields including: `client` (Link→Customer), `hospital` (Link→Customer), `hospital_branch` (Data), `client_location_warehouse` (Link→Warehouse, reqd), `doctor_name` (Data), `surgery_date` (Date), `surgery_set_type` (Link→Collection Set), `workflow_state` (Select, read-only), `dispatch_group_id` (Data), `delivery_person` / `return_pickup_delivery_person` (Link→User), `shortage_note` (Long Text, read-only), `packed_scan_log` / `returned_scan_log` (Long Text), 5 Stock Entry link fields (read-only), `sales_invoice` (Link, read-only), 3 Task link fields (read-only), `case_items` (Table→Surgery Case Item), `tool_serial_exceptions` (Table→Surgery Case Serial Exception)
- Permissions: `Ops - Order Accepting` (R/W/Create), `Ops - Inventory` (R/W), `Ops - Delivery` (R/W), `Ops - Returns` (R/W), `Ops - Accounting` (R/W), `Delivery Driver` (R)

**Custom Fields on existing DocTypes:**
- `Task-surgery_case`: Link → Surgery Case (after `dispatch_group_id`)
- `Stock Entry-surgery_case`: Link → Surgery Case (after `sales_order`)
- `Stock Entry-dispatch_group_id`: Data (after `surgery_case`)
- `Sales Invoice-surgery_case`: Link → Surgery Case (after `doctor_name`)

**Workflow — `Surgery Case Workflow`** (12 states, 11 transitions, `is_active=1`):
| State | allow_edit | Transition Out |
|---|---|---|
| Draft | Ops - Order Accepting | Start Preparing → Preparing |
| Preparing | Ops - Order Accepting | Move to Dispatch Picking |
| Dispatch Picking | Ops - Inventory | Mark as Dispatched |
| Dispatched | Ops - Delivery | Mark as Delivered |
| Delivered | Ops - Order Accepting | Schedule Return Pickup |
| Return Pickup Scheduled | Ops - Delivery | Mark Pickup In Transit |
| Return Pickup In Transit | Ops - Returns | Start Returns Verification |
| Returns Verification | Ops - Returns | Mark Returns Received |
| Returns Received | Ops - Returns | Derive Usage |
| Usage Derived | Ops - Accounting | Create Invoice |
| Invoiced | Ops - Order Accepting | Close Case → Closed |
| Closed | System Manager | (terminal) |

**Server Script — `Surgery-Case-before-save`** (DocType Event: Before Save on Surgery Case):
- On first save in Draft: auto-loads `case_items` from the linked `Collection Set` template.
- While in Draft: runs non-blocking stock availability check against `Main - Inmed`, writes `shortage_note`.
- Auto-creates Delivery Task (kind: "Delivery") when `delivery_person` is set after Dispatch Picking — idempotent.
- Auto-creates Return Pickup + Return Drop-off Tasks when `return_pickup_delivery_person` is set in "Return Pickup Scheduled" state — idempotent.
- **Preparing → Dispatch Picking**: blocking stock gate on `Main - Inmed`; creates draft Dispatch SE (`Main → Delivery In-Transit`).
- **Dispatch Picking → Dispatched**: validates Dispatch SE is submitted (`docstatus=1`).
- **Dispatched → Delivered**: validates Delivery Task status = "Completed"; auto-creates and submits Delivery SE (`Delivery In-Transit → Client Location Warehouse`).
- **Return Pickup Scheduled → Return Pickup In Transit**: validates Pickup Returns Task status = "Completed".
- **Return Pickup In Transit → Returns Verification**: validates Return Drop-off Task status = "Completed"; creates two draft return SEs — pickup SE (`Client Location → Return Pickup In-Transit`, backdated to task completion time) and receive SE (`Return Pickup In-Transit → Returns`).
- **Returns Verification → Returns Received**: validates both return SEs are submitted.
- **Returns Received → Usage Derived**: computes `used_qty = dispatched - returned - lost_damaged` per row; auto-creates and submits Consumption SE (`Material Issue` from Client Location); handles serial-tracked items (requires missing serials in `tool_serial_exceptions`), batch-tracked items (issues by batch), and non-tracked items.
- **Usage Derived → Invoiced**: creates draft Sales Invoice with `update_stock=0`, pre-fills `hospital`, `hospital_branch`, `doctor_name`, and `surgery_case` link fields.
- **Invoiced → Closed**: final serial accountability gate — all dispatched serials must either be returned or listed in `tool_serial_exceptions`.
- All SE/Task/Invoice creation is idempotent (guards against double-creation on re-save).
- Script uses `_run()` wrapper function for internal `return` statement compatibility in Frappe safe_exec.

**Client Script — `Surgery-Case-field-locking`**:
- `dispatched_qty`: editable only in Draft/Preparing/Dispatch Picking states.
- `returned_qty` + `lost_damaged_qty`: editable only in Return Pickup In Transit/Returns Verification states.
- `used_qty`: always read-only (computed by server).

### ~~Pending / To-Do (Doc 12A)~~ OBSOLETE (deleted 2026-08-28)
- ~~**[ ]** Assign real staff~~ — roles still exist; used by Dispatch Case workflow
- ~~**[ ]** Create real `Surgery Case` records~~ — **DELETED**: entire system removed
- ~~**[ ]** Configure `client_location_warehouse`~~ — done via Dispatch Case flow
- ~~**[ ]** Enable serial/batch tracking~~ — still relevant for Dispatch Case
- ~~**[ ]** Verify Task `task_kind` options~~ — still relevant for Dispatch Case
- ~~**[ ]** Clean up stray Workflow Action Master `"TestAction888"`~~ — Workflow deleted

### Notes / Known Issues (Doc 12A)
- **`Workflow State` and `Workflow Action Master` must pre-exist**: Frappe v14 validates `Workflow Document State.state` as a Link→`Workflow State` and `Workflow Transition.action` as a Link→`Workflow Action Master`. The deploy script now creates all 12 states and 11 action master records before creating the Workflow document.
- **`workflow_action_name` field** (not `workflow_action_master_name`): The `Workflow Action Master` DocType autonames from the `workflow_action_name` field. Using the wrong field name causes a validation error. Fixed in the deploy script.
- **`allow_edit` is mandatory** on `Workflow Document State`: Each state row must include a `allow_edit` (Link→Role) specifying which role can edit the document in that state. Omitting this causes `MandatoryError`. Fixed by assigning the owning role per state.
- **`doc_status` in states uses string `"0"`** (not integer): Frappe's Select field expects string values.
- Server script uses `_run()` wrapper for `return` statement support in Frappe's safe_exec sandbox.

---

## Doc 13A — Reporting Pack

**Deployed:** 2026-05-08  
**Script:** `deploy/doc13a-deploy.ps1`  
**Mode:** `Check` then `Deploy`

### What was deployed

**16 Query Reports** (all `report_type = "Query Report"`, `is_standard = "No"`):

| Report name | Ref DocType | Filters |
|---|---|---|
| `RPT — Stock — Client Locations (All)` | Bin | Warehouse, Item Group, Item |
| `RPT — Stock — Delivery In-Transit - Inmed` | Bin | — |
| `RPT — Stock — Return Pickup In-Transit - Inmed` | Bin | — |
| `RPT — Stock — Returns - Inmed` | Bin | — |
| `RPT — Stock — In-Transit Stuck (Age Check)` | Stock Ledger Entry | Min Days (default 1) |
| `RPT — Stock — Near Expiry (Main - Inmed)` | Stock Ledger Entry | Near Expiry Days (default 30) |
| `RPT — Ops — Driver Task Queue (Derived)` | Task | Assigned To |
| `RPT — Ops — Prepaid Orders Awaiting Delivery` | Sales Order | Customer |
| `RPT — Ops — Client Stock With No Open Cases` | Warehouse | — |
| `RPT — Surgery Cases — Aging (Open)` | Surgery Case | Min Age Days (default 0) |
| `RPT — Receivables — Unpaid Invoices (Aging)` | Sales Invoice | Customer, From Date, To Date |
| `RPT — Receivables — Unallocated Advances` | Payment Entry | Customer |
| `RPT — Risk — Debt Threshold Exceeded` | Customer | — |
| `RPT — Sales — History by Client` | Sales Invoice | Customer, From Date, To Date |
| `RPT — Data Quality — Tracked Items Missing Identifiers` | Stock Entry | — |
| `RPT — Pricing — Sales Orders With Manual Rate Edits` | Sales Order | — |

**1 Workspace** (`Ops — Reporting Pack`, Public):  
- 28 shortcuts: all 16 reports + 4 DocType shortcuts for Surgery Case state views + 6 Task queue DocType shortcuts + 2 legacy views (Collection Sets, Price Overrides)

### Warehouse names in SQL
All queries use `- Inmed` suffix (e.g., `'Main - Inmed'`, `'Clients - Inmed'`), not `- WH` as shown in the doc template.

### What requires manual steps (not deployable via REST API)
Named saved list views cannot be shared across users via the REST API in Frappe v14. The following views from Doc 13A §5.7 and §5.13 must be created manually per user or by a System Manager opening the relevant DocType list, applying filters, and saving:

- `VIEW — Surgery Cases — Delivered (Awaiting Pickup)` — filter: `workflow_state = Delivered`
- `VIEW — Surgery Cases — Return Pickup In Transit` — filter: `workflow_state = Return Pickup In Transit`
- `VIEW — Surgery Cases — Returns Received (Awaiting Usage)` — filter: `workflow_state = Returns Received`
- `VIEW — Surgery Cases — Usage Derived (Awaiting Invoice)` — filter: `workflow_state = Usage Derived`
- `VIEW — Tasks — Debt Collection (Open)` — filter: `task_kind = Debt Collection`, status not Completed/Cancelled
- `VIEW — Tasks — Distribute Payment (Open)` — filter: `task_kind = Distribute Payment`
- `VIEW — Tasks — Return to warehouse (Open)` — filter: `task_kind = Return to warehouse (aborted delivery / cancelled order)`
- `VIEW — Tasks — Discount Approval (Open)` — filter: `task_kind = Discount Approval`
- `VIEW — Tasks — Purchase Approval (Open)` — filter: `task_kind = Purchase Approval`
- `VIEW — Tasks — Write-off Approval (Open)` — filter: `task_kind = Write-off Approval`
- `Price Overrides — by Client` — Item Price list, filter: `selling=1, customer != ""`
- `Collection Sets — Readiness` — Collection Set list with readiness columns

**Workaround**: The `Ops — Reporting Pack` workspace shortcuts include DocType shortcuts with `stats_filter` JSON for the same queues — these are clickable from the workspace and behave like the named views.

### Known issues / encoding note
- PowerShell 5.1 on Windows reads UTF-8 files without BOM using the system locale encoding (often Windows-1252). The em dash character `—` (U+2014, bytes `E2 80 94` in UTF-8) is decoded as `â€"` in Windows-1252, where byte `0x94` = RIGHT DOUBLE QUOTATION MARK (U+201D), which PowerShell treats as a string terminator. **Fix**: defined `$EM = [char]0x2014` and used `${EM}` string interpolation throughout the script — no em-dash literal appears in code.

### To-Do (Doc 13A)
- **[ ]** Roles: ensure `Ops - Order Accepting`, `Ops - Inventory`, `Accounting`, `Director` roles can access the `Ops — Reporting Pack` workspace.
- **[ ]** Create manual list views listed above (per-team per user, or by System Manager).
- **[ ]** Validate `RPT — Surgery Cases — Aging (Open)` once first Surgery Cases are created.
- **[ ]** Validate `RPT — Risk — Debt Threshold Exceeded` — requires `debt_threshold_amd` custom field on Customer (deployed by Doc 09A/04A).
- **[ ]** Validate `RPT — Ops — Driver Task Queue (Derived)` — requires `task_kind`, `surgery_case`, `dispatch_group_id` custom fields on Task (deployed by Doc 10A/12A).

---

## Doc 14 — Go-Live Readiness Checklist

**Type:** Human team activity — no deployment script.  
**Reference:** `docs/14-go-live-checklist.md`

Doc 14 is a pre-go-live team meeting checklist. It has no ERPNext artefacts to deploy. Run it with Operations lead, Accounting lead, Purchasing lead, and a Director before the first real transaction.

### Go / No-Go minimum criteria (from Doc 14 §3)
- Can run one complete **standard sale** end-to-end (order → dispatch → delivery → invoice) with correct stock movements.
- Can run one complete **surgery case** end-to-end (dispatch → deliver → return pickup → returns verification → usage derived → invoice) with correct batch/serial behaviour.
- Directors can see open approvals, clients above debt threshold, and received payments pending distribution.
- Purchasing can see a reorder list grouped by supplier.

### Pre-go-live technical checklist (system side)

| Area | Status | Notes |
|---|---|---|
| Roles exist (Doc 03A) | ✅ | Deployed |
| Warehouse tree (Doc 05A) | ✅ | Deployed |
| Items + tracking flags (Doc 06A) | ✅ | Imported |
| Reorder setup (Doc 08A) | ⬜ | Thresholds need per-item review |
| Debt threshold automation (Doc 09A) | ✅ | Scheduled script deployed |
| Task system (Doc 10A) | ✅ | Deployed |
| Collection Set templates (Doc 11A) | ❌ | **DELETED 2026-08-28** — never used, superseded by Dispatch Case |
| Surgery Case workflow (Doc 12A) | ❌ | **DELETED 2026-08-28** — never used, superseded by Dispatch Case |
| Reporting pack (Doc 13A) | ✅ | Deployed |
| Staff assigned to operational roles | ⬜ | Pending |
| Doctor client-location warehouses exist | ⬜ | Warehouses exist; verify all active doctors have one |
| Serial/batch tracking enabled on Item masters | ⬜ | Enable per item group |
| Reorder thresholds set per item | ⬜ | Phase 1 can use minimal thresholds |

### End-to-end test scenarios to run before go-live (Doc 14 §9)
- **Scenario A** — Standard sale: order → dispatch → delivery → partial payment → unallocated advance → debt reporting
- **Scenario B** — Discount approval gate: order with discount → director approval → delivery unblocked
- **Scenario B1** — Cancellation redirect: cancel in-transit order → return-to-warehouse task → stock via Returns → Main
- **Scenario C** — Debt threshold escalation: exceed threshold → Debt Collection task auto-created
- **Scenario D** — Procurement: draft PO → director approval → goods receipt → supplier invoice
- **Scenario E** — Reorder list: low-stock items appear, grouped by supplier
- ~~**Scenario F** — Surgery case end-to-end~~ — **REMOVED**: Surgery Case deleted 2026-08-28, superseded by Dispatch Case (Scenario A covers this flow)
- **Scenario G** — Permanent set replenishment (if applicable)

### To-Do (Doc 14 — go-live gate)
- **[ ]** Schedule go-live readiness meeting with all team leads.
- **[ ]** Run Scenario A–F in a staging/test environment and sign off each.
- **[ ]** Confirm all "⬜" items in the table above are resolved or formally deferred with an owner + date.
- **[ ]** Confirm Doc 13A reporting views are usable by each team before first real transaction.

---

## Doc 15A — Reporting Requirements: Phase 1–4

**Deployed:** 2026-05-12  
**Scripts:** `deploy/doc15a-deploy.ps1`, `deploy/doc15b-deploy.ps1`, `deploy/doc15c-deploy.ps1`  
**Mode:** `Check` then `Deploy` (all three in sequence)

### What was deployed

**1 Custom Field:**

| DocType | Fieldname | Type | Default | Purpose |
|---|---|---|---|---|
| `Item Reorder` | `buffer_percentage` | Float | 0.20 | Safety stock buffer for norm calculation (§7.1). Extends Doc 08 static threshold system. |

**18 new Query Reports:**

| Report name | Ref DocType | Roles | Script |
|---|---|---|---|
| `RPT — Stock — Balance Multi-Select` | Bin | All Ops + Directors | doc15a |
| `RPT — Stock — Batch and Expiry Balance` | Stock Ledger Entry | Inventory, Returns, Directors | doc15a |
| `RPT — Stock — Expiry Classification` | Item | Inventory, Purchasing, Directors | doc15a |
| `RPT — Stock — Entries by Period` | Stock Entry | All Ops + Directors | doc15a |
| `RPT — Stock — Warehouse Movement` | Stock Entry | Inventory, Order Accepting, Returns, Driver, Directors | doc15a |
| `RPT — Sales — Sold Items Detail` | Sales Invoice | **Directors only** (profit columns) | doc15a |
| `RPT — Accounting — Sales Documents and Payments` | Sales Invoice | Accounting, Directors | doc15a |
| `RPT — Accounting — Debt Status Board` | Sales Invoice | Accounting, Directors | doc15b |
| `RPT — Accounting — Income by Period` | Sales Invoice | **Directors only** | doc15b |
| `RPT — Purchasing — Norm and Reorder` | Item | Purchasing, Directors | doc15b |
| `RPT — Sales — Top Products` | Sales Invoice | All Ops + Directors | doc15b |
| `RPT — Sales — Top Customers` | Sales Invoice | Order Accepting, Accounting, Directors | doc15b |
| `RPT — Sales — Comparative Periods` | Sales Invoice | **Directors only** | doc15c |
| `RPT — Stock — Slow-Moving Products` | Bin | Inventory, Purchasing, Directors | doc15c |
| `RPT — Stock — Near Expiry Value at Risk` | Stock Ledger Entry | Inventory, Accounting, Directors | doc15c |
| `RPT — Data Quality — Missing Doctor or Hospital` | Sales Invoice | Order Creating, Accounting, Directors | doc15c |
| `RPT — Data Quality — Negative Stock` | Bin | Inventory, Directors | doc15c |
| `RPT — Purchasing — Supplier Performance` | Purchase Order | Purchasing, Directors | doc15c |

**Workspace updated:** `Ops — Reporting Pack` — expanded from 28 to 46 shortcuts (all new reports added; existing shortcuts preserved).

### Notes

- `buffer_percentage` field defaults to `0.20` (20%) when null — the Norm and Reorder report uses `coalesce(ir.buffer_percentage, 0.20)`.
- `RPT — Sales — Sold Items Detail` joins `tabItem Price` (price_list = `Standard Buying`) for gross profit. Profit columns will show 0 until Standard Buying prices are populated (Doc 06 pending item).
- `RPT — Stock — Near Expiry Value at Risk` similarly shows `value_at_risk = 0` until buying prices exist.
- Reports excluded from this deployment (New Scope / Phase 3+ deferred): Global Statistics Dashboard (§8.4), Return/Refund Money function (§6.6), Task auto-escalation (§8.2 auto). These are tracked in `docs/15a-reporting-requirements-implementation.md`.

### To-Do (Doc 15A)

- **[ ]** Validate `RPT — Purchasing — Norm and Reorder` once `Item Reorder` rows have `buffer_percentage` values entered by purchasing team.
- **[ ]** Validate profit columns in `RPT — Sales — Sold Items Detail` and `RPT — Stock — Near Expiry Value at Risk` after Standard Buying prices are populated.
- **[ ]** Confirm `RPT — Sales — Comparative Periods` filter date ranges are intuitive for directors.
- **[ ]** Review workspace shortcut order with operations lead — reorder if needed via doc15c re-run.

---

## Surgery Case System Deletion (2026-08-28)

**Reason:** The entire Surgery Case system (Docs 11A, 12A) was deployed but **never used** — 0 records ever created. It has been fully superseded by the Unified Dispatch Case flow (Doc 16). Verified on production (cloned to test 2026-07-15): zero Surgery Cases, zero Collection Sets, zero linked Tasks/Stock Entries/Invoices.

### What Was Deleted (from test.erpnext.am)

**Server Scripts (3):**
- `Surgery-Case-before-save` — 279-line orchestrator on Surgery Case
- `Collection-Set-validate-readiness` — stock readiness check on Collection Set
- `Surgery-Set-Type-validate-readiness` — duplicate of above

**Client Scripts (2):**
- `Surgery-Case-field-locking` — field lock by workflow state
- `Task - Load Surgical Kit Template` — dead code (targeted Dispatch Case from Task context, loaded from Collection Set)

**Workflow (1):**
- `Surgery Case Workflow` — 12 states, 11 transitions, `is_active=1` but never exercised

**Custom Fields (4):**
- `Task-surgery_case` (Link → Surgery Case)
- `Stock Entry-surgery_case` (Link → Surgery Case)
- `Sales Invoice-surgery_case` (Link → Surgery Case)
- `Task-custom_select_surgical_kit_template` (Link → Surgical Kit Template, 0 Tasks used it)

**Custom DocTypes (5):**
- `Surgery Case Serial Exception` (child table)
- `Surgery Case Item` (child table)
- `Surgery Case` (parent)
- `Collection Set Item` (child table)
- `Collection Set` (parent)

**Field removed from Dispatch Case DocType:**
- `surgery_set_type` (Link → Collection Set) — 0 Dispatch Cases used it

**Dispatch Case-Form client script edited:**
- Removed `surgery_set_type` handler and hide-line (dead code referencing deleted Collection Set)

### What Was Preserved (actively used)

- `Surgical Kit Template` DocType — 1 record ("Hip Surgery Standard Kit"), 16 Dispatch Cases reference it
- `Dispatch Case-Template Auto Fill.js` — loads items from Surgical Kit Template
- `custom_select_surgical_kit_template` field on Dispatch Case — actively used

### Pending (Prod)
- **[ ]** Execute same deletions on `erpnext.am` (prod) when ready
- **[ ]** Docs 11, 11A, 12, 12A are now historical — consider archiving or adding deprecation headers
