# ERPNext Go-Live Handover Summary

**Prepared:** 2026-05-19  
**Project:** Muselimyan / Inmed ERPNext go-live  
**Purpose:** single detailed handover document showing what is already done, what remains, what is safe to defer, and what must not be changed carelessly.

---

## 1. Executive Summary

The ERPNext system is now much closer to go-live than before. The two biggest technical blockers discussed recently were:

1. **Role Permission Manager setup**
2. **Item tracking flags before first stock transaction**

Both are now effectively complete from the technical/setup side:

- **Role Permission Manager:** completed manually in ERPNext UI by the user. API verification was limited by ERPNext/permission API behavior, but the user confirmed the permissions are visible and persisted after refresh/reopen.
- **Item tracking flags:** completed, applied, and verified against the approved V3 item-level classification.

The main remaining work is no longer bulk technical setup. It is mostly:

- assigning real staff users and removing/locking example users,
- running end-to-end smoke tests,
- finalizing buying prices and item costing/tax master data,
- confirming/deploying or smoke-testing the Purchase Receipt barcode workflow,
- setting reorder thresholds,
- creating manual saved views if desired,
- team training and go/no-go signoff.

**Most important current status:** Item master tracking flags now match the approved classification exactly:

```text
BATCH_EXPIRY: 743 items
REF_ONLY: 2575 items
Total reviewed/applied: 3318 items
Missing: 0
Ambiguous: 0
Errors: 0
Would update after apply: 0
```

---

## 2. Completed Major Work

### 2.1 Roles and permissions

#### Completed

- Operational roles exist, including:
  - `Ops - Order Accepting`
  - `Ops - Inventory`
  - `Ops - Returns`
  - `Ops - Delivery`
  - `Ops - Accounting`
  - `Ops - Directors`
  - `Delivery Driver`
  - `Ops - Order Creating`
  - `Ops - Finance`
  - `Ops - Purchasing`
  - `Ops - Purchasing Lead`
- Role Permission Manager setup for the critical DocTypes was completed manually in ERPNext UI.
- User confirmed that Role Permission Manager rows remained visible after refresh/close/open.
- API diagnostics could not fully verify permission internals because ERPNext returned permission/API limitations (`403` / `417`) for some permission internals. This is recorded as an API limitation, not a confirmed setup failure.

#### Important permissions table to keep for troubleshooting

If a user gets `Permission Denied`, compare against this intended setup:

| DocType / Area | Role | Intended access |
|---|---|---|
| `Dispatch Case` | `Ops - Order Creating` | Read, Write, Create, Submit |
| `Dispatch Case` | `Ops - Order Accepting` | Read |
| `Dispatch Case` | `Ops - Accounting`, `Ops - Inventory`, `Ops - Returns`, `Delivery Driver` | Read |
| `Dispatch Case` | `Ops - Directors` | Read, Cancel |
| `Stock Entry` | `Ops - Inventory`, `Ops - Delivery`, `Ops - Returns` | Read, Write, Create, Submit |
| `Stock Entry` | `Delivery Driver` | No access |
| `Sales Invoice` | `Ops - Accounting` | Read, Write, Create, Submit, Cancel |
| `Sales Invoice` | `Ops - Finance` | Read |
| `Payment Entry` | `Ops - Accounting` | Read, Write, Create, Submit, Cancel |
| `Payment Entry` | `Ops - Finance` | Read, Write, Create, Submit, Cancel |
| `Task` | `Ops - Finance` | Read, Write own tasks only, enforced by script |
| `Item`, `Item Group`, `Item Attribute`, `UOM` | `Ops - Inventory`, `Ops - Directors` | Write, Create |
| `Item`, `Item Group`, `Item Attribute`, `UOM` | other operational roles | Read only |
| `Ops — Reporting Pack` workspace | relevant ops/reporting roles | accessible |

#### Do not do

- Do **not** give `System Manager` to normal daily operational staff to bypass permission errors.
- `System Manager` bypasses many governance controls and should remain restricted.

---

### 2.2 Item tracking flags

#### Completed

A strict item-level classification was created and applied.

Final approved tracking strategy:

| Category | ERPNext flags | Meaning |
|---|---|---|
| `BATCH_EXPIRY` | `has_batch_no = 1`, `has_expiry_date = 1`, `has_serial_no = 0` | Product must be tracked by item REF + LOT + expiry |
| `REF_ONLY` | `has_batch_no = 0`, `has_expiry_date = 0`, `has_serial_no = 0` | Product is identified by item REF only; quantity tracking only |

Final verified counts:

```text
BATCH_EXPIRY: 743
REF_ONLY: 2575
MANUAL_REVIEW: 0
HIGH risk: 0
Total review rows: 3318
```

Final ERPNext update verification:

```text
Mode: DRY-RUN
Review rows: 3318
ERPNext Items fetched: 3265
BATCH_EXPIRY review rows: 743
REF_ONLY review rows: 2575
Already OK: 3318
Would update: 0
Missing: 0
Ambiguous: 0
Errors: 0
```

#### Files created/used

| File | Purpose |
|---|---|
| `deploy/generate_item_tracking_review.py` | Generates V3 item classification files from `1c/items.csv` |
| `deploy/item-tracking-review-v3.csv` | Final approved item-level tracking decision file |
| `deploy/item-tracking-group-summary-v3.csv` | Final group-level summary |
| `deploy/update_item_tracking_flags.py` | Dry-run/apply script that compares V3 against ERPNext and applies changes only with `--apply` |
| `deploy/item-tracking-update-dry-run.csv` | Latest verification report after apply |
| `deploy/item-tracking-update-errors.csv` | Error report; final state had `Errors: 0` |

#### Classification rules that were applied

- Non-sterile products are `REF_ONLY`.
- Sterile products are `BATCH_EXPIRY`.
- No serial tracking was enabled for go-live.
- Reusable instrument sets/surgery sets are non-sterile and `REF_ONLY`.
- Blank item rows without identity are skipped.
- All plates are `REF_ONLY`.
- All nails are `REF_ONLY`.
- `I.N.`, `Intr. Nail`, and `Intramedullary` were treated as nail indicators and therefore `REF_ONLY`.
- Usual screws are `REF_ONLY`.
- Chunli / Permedica / Just screws are `BATCH_EXPIRY`.
- Prosthesis components are generally `BATCH_EXPIRY` unless clearly instrument/tool/set.
- Cement, Teknimed Cement, ViscoPhi, Albomed and similar sterile materials are `BATCH_EXPIRY`.
- BPB RENOVA SPINE Kyphoplasty Kit and VERTEBROPLASTIC products are `BATCH_EXPIRY`.
- SOPHYSA PRESSIO kits, drainage systems, catheters, valves, reservoirs are `BATCH_EXPIRY`.
- ConMed GENESYS MATRYX Interference Screw and BIOSCREW are `BATCH_EXPIRY`.

#### Final actual changes applied

Only 4 ERPNext Items required actual updates after the final classification cleanup:

| SKU/REF | Description | Final tracking |
|---|---|---|
| `KB25` | BMK Barclay PMMA bone cement | `BATCH_EXPIRY` |
| `01-0350` | Spinos radiopaque syntetic resin for spine surgery 24G | `BATCH_EXPIRY` |
| `2951453/25` | Alcasis, Bone Cement Surgical Vertebroplast 20G | `BATCH_EXPIRY` |
| `880223` | Synicem 1G 40g | `BATCH_EXPIRY` |

Apply result:

```text
Updated: 4
Errors: 0
```

Post-apply verification showed no further changes needed.

#### Do not do

- Do **not** bulk-enable batch/expiry for all items.
- Do **not** enable serial tracking unless the business explicitly decides to track individual physical instruments one by one.
- Do **not** change tracking flags after stock transactions begin unless ERPNext permits it for that item and the business fully understands the data consequences.

---

### 2.3 Master data and catalog status

#### Completed or mostly completed

- 1C item data was used for the 3318-row item tracking classification.
- ERPNext Items now match the final tracking strategy.
- `custom_1c_code` is used as an additional matching key for item identity.
- `Standard Selling` price data exists according to prior status documents.
- Item costing support from Doc 17A was deployed:
  - `Item-hs_code` custom field
  - `Item-import_tax_rate` custom field
  - `LCV-import-duty-prefill` client script

#### Remaining

- Populate `hs_code` and `import_tax_rate` for imported items.
- Populate `Standard Buying` item prices if profit/margin reports are needed.
- Confirm `Standard Selling` prices are complete for all sellable items after the 3200+ item expansion.
- Decide whether to clean up item group hierarchy and naming convention.

#### Item group/naming decisions still open

These are not blockers for first transaction unless management wants clean reporting immediately:

| Decision | Status | Impact |
|---|---|---|
| Type-first item group hierarchy vs brand-first hierarchy | Not finalized | Affects reporting/filtering quality |
| Item naming convention `<Brand> — <Name> — <Spec>` | Not finalized | Cosmetic/search quality; item codes remain stable |
| More Item Attribute values | Ongoing | Useful for future variant/template structure |

---

### 2.4 Warehouses and stock rules

#### Completed

Core warehouse model exists:

- `Main - Inmed`
- `Delivery In-Transit - Inmed`
- `Return Pickup In-Transit - Inmed`
- `Returns - Inmed`
- `Clients - Inmed` group warehouse
- Client-location leaf warehouses under `Clients - Inmed`

Known stock settings/rules:

- Negative stock is disabled.
- Valuation method is FIFO.
- Stock auth role is `Ops - Inventory`.
- Operational scripts assume `Main - Inmed`; do not randomly introduce another main warehouse.

#### Remaining

- Verify every active doctor/client that needs client-location stock has a correct child warehouse under `Clients - Inmed`.
- When creating new client warehouses, follow the code/name pattern used in the existing warehouse cleanup.

---

### 2.5 Task system

#### Completed

Task system foundations are deployed:

- `task_kind` field exists and includes the operational task kinds.
- `Task Access Policy` records exist, including policies used by Dispatch Case and approval flows.
- Task governance script exists and enforces:
  - owning-team edit rules,
  - completion permissions,
  - one-owner rule for active/completed tasks,
  - required delivery/return photos where applicable,
  - `completed_at` stamping.

Task kinds/policies include:

- `Order entry`
- `Pack / prepare items`
- `Dispatch picking / hand-off`
- `Delivery`
- `Pickup Returns`
- `Return drop-off at warehouse`
- `Returns processing / verification`
- `Returns restocking`
- `Invoice preparation / create invoice`
- `Debt Collection`
- `Distribute Payment`
- `Payment Received`
- `Discount Approval`
- `Purchase Approval`
- `Write-off Approval`
- `Return to warehouse (aborted delivery / cancelled order)`

#### Remaining

- Assign real staff users to the correct roles.
- Replace or disable example/team-placeholder login users as appropriate.
- Review existing Tasks in `Working` / `Completed` status that have 0 or more than 1 assignee; fix or cancel them before go-live.
- Create optional Directors TV/wallboard user if needed.

---

### 2.6 Unified Dispatch Case flow

#### Completed

Doc 16A unified dispatch flow was deployed according to `docs/16b-unified-dispatch-flow-gap-analysis.md`:

```text
2026-05-11: doc16a-deploy.ps1 -Mode Deploy
Result: COMPLETE, exit code 0, all items exists:true in verification
```

This supersedes older separate Sales Order / Surgery Case operational flows from Docs 09 and 12. The newer system uses `Dispatch Case` as the unified operational document.

Doc 16A deployment included:

- roles and team users,
- extra task kinds,
- task access policies,
- `Dispatch Case` custom DocType and child tables,
- custom fields on Task and related documents,
- server scripts for state machine automation,
- task chaining,
- stock movement automation,
- payment/debt/discount task logic,
- workspace shortcuts.

#### Important conceptual flow

For cases with no returns:

```text
Order entry → Dispatch Case → Pack/prepare → Delivery → Invoice → Payment/Debt follow-up → Closed
```

For return-expected cases:

```text
Order entry → Dispatch Case → Pack/prepare → Delivery → Return pickup → Returns verification → Restock/usage → Invoice → Payment/Debt follow-up → Closed
```

#### Remaining

- End-to-end smoke tests must be run before first real transaction.
- Real staff must be assigned to roles before the task governance rules are meaningful.
- Team must be trained not to bypass the Dispatch Case state machine.

#### Do not do

- Do **not** manually move stock to client-location warehouses outside the Dispatch Case automation.
- Do **not** manually skip in-transit warehouses.
- Do **not** edit Dispatch Case status directly to jump steps.
- Do **not** enable invoice `Update Stock` for stock movements that should be controlled by Dispatch Case.

---

### 2.7 Purchasing, Purchase Orders, Purchase Receipts, costing

#### Completed

From Docs 07/08/17A and current status:

- Purchase Order director approval gate exists.
- PO approval task writeback exists.
- Re-approval trigger exists when approved draft PO lines/header change.
- Purchase Receipt destination gate exists: rows should land in `Main - Inmed`.
- Purchase Receipt batch/expiry gate exists for batch+expiry items.
- Purchase Invoice `Update Stock` gate exists: PI with `update_stock = 1` should be blocked.
- Reorder governance script exists: changing reorder rows requires `Reorder Change Reason` and correct role.
- Import costing support exists:
  - Item `hs_code`
  - Item `import_tax_rate`
  - Landed Cost Voucher import duty prefill client script

#### Remaining

- Assign real staff to `Ops - Purchasing` and `Ops - Purchasing Lead`.
- Populate reorder thresholds on items that need reorder management.
- Ensure reorder warehouse is always `Main - Inmed`.
- Populate `purchase_reason` and `requested_by` on any existing draft Purchase Orders before users try to save/submit them.
- Populate `hs_code` and `import_tax_rate` on imported items.
- Populate `Standard Buying` prices so margin reports work.
- Smoke-test:
  - PO submit blocked until Director approval,
  - approval task approves PO,
  - edited approved draft PO resets to pending,
  - PR cannot submit to non-`Main - Inmed`,
  - batch+expiry PR item requires batch and expiry,
  - PI with `Update Stock` checked is blocked,
  - LCV import duty prefill works.

---

### 2.8 Reports and workspace

#### Completed

Reporting pack is deployed.

Doc 13A deployed:

- 16 Query Reports
- `Ops — Reporting Pack` workspace
- shortcuts for reports and operational queues

Doc 15A/B/C deployed additional management reports:

- stock balance multi-select,
- batch and expiry balance,
- expiry classification,
- warehouse movement,
- sales sold items detail,
- accounting debt status board,
- income by period,
- purchasing norm and reorder,
- top products/customers,
- comparative sales periods,
- slow-moving products,
- near-expiry value at risk,
- data quality reports,
- supplier performance.

Workspace was expanded to include the newer reports.

#### Remaining

- Validate reports with real or test transaction data.
- Profit/value reports will show incomplete/zero values until Standard Buying prices are populated.
- Create optional manual saved views if the team wants named list views in addition to workspace shortcuts.

Manual saved views that may still be useful:

| View | Where to create |
|---|---|
| `Stock Balance — Main - Inmed` | Search for `Stock Balance`, filter Warehouse = `Main - Inmed`, save view/report filter |
| `Items — Active Stock` | Search for `Item`, filter Disabled = No, Is Stock Item = Yes, save view |
| `Reorder — Main - Inmed` | Search for `Stock Reorder`, filter Warehouse = `Main - Inmed` |
| `Price Overrides — by Client` | Search for `Item Price`, filter Price List = Standard Selling and Customer not blank |
| Dispatch Case state views | Search for `Dispatch Case`, filter by status/workflow state |
| Task queue views | Search for `Task`, filter by `task_kind` and status not Completed/Cancelled |

Note: workspace shortcuts already cover many of these queues, so saved views are helpful but not necessarily blocking.

---

### 2.9 Purchase Receipt barcode scanning / GS1 logic

#### Current status

Barcode scanning has a prepared implementation and documented behavior. There is also a deployment script:

```text
deploy/barcode-gs1-deploy.ps1
```

The readiness document says the implementation was prepared locally and requires careful check/deploy/verify flow.

Agreed behavior:

1. Scan REF barcode in the main Purchase Receipt scanner field.
2. ERPNext standard barcode logic finds the item.
3. Operator scans the second GS1 barcode in the row barcode field.
4. Script parses:
   - AI `11` production date,
   - AI `17` expiry date,
   - AI `10` LOT/batch number.
5. Script fills:
   - `batch_no`,
   - expiry field,
   - `custom_production_date`,
   - `custom_scanned_gs1_barcode`.
6. Same item + same LOT + same expiry can merge quantity.
7. Same item + same LOT + different expiry must stay separate.
8. Expired and future-production exceptions require approved override and reason.
9. Expiry alerts:
   - 180 days or less: notice,
   - 90 days or less: stronger warning,
   - expired: block unless override.

#### Important limitation

The second barcode does **not** identify the item. Operational rule:

```text
Scan one physical product at a time: REF barcode first, then second GS1 barcode from the same package immediately.
```

#### Remaining

- Confirm whether `GS1 Barcode Parser` and the six custom fields are already deployed in production.
- If not confirmed, run check/deploy/check using the deployment script.
- Browser/manual smoke test the scanner flow on Purchase Receipt.
- Confirm override fields are permission-restricted to Directors / Inventory Manager level users if required.
- Add or verify server-side validation later if client-only validation is considered insufficient.

#### Commands from readiness document

Check mode:

```powershell
.\deploy\barcode-gs1-deploy.ps1 -Mode Check
```

Deploy mode:

```powershell
.\deploy\barcode-gs1-deploy.ps1 -Mode Deploy
```

Check again:

```powershell
.\deploy\barcode-gs1-deploy.ps1 -Mode Check
```

Expected after deployment:

- all six barcode custom fields exist,
- `GS1 Barcode Parser` exists,
- enabled = `1`,
- dt = `Purchase Receipt`.

Smoke test examples:

REF barcode:

```text
]C10106938250917530
```

Second GS1 barcode:

```text
]C111250425173004241025D086
```

Expected parsed values:

```text
Production Date: 2025-04-25
Expiry Date: 2030-04-24
Batch No: 25D086
Raw GS1 Barcode: ]C111250425173004241025D086
```

---

## 3. What Remains Before Go-Live

This is the most important section if quota ends.

### Priority 1 — must finish before first real transaction

#### 1. Assign real users and roles

Create/confirm real staff accounts and assign roles:

| Team | Needed roles |
|---|---|
| Order creation | `Ops - Order Creating` |
| Order acceptance / dispatch coordination | `Ops - Order Accepting` |
| Inventory / warehouse | `Ops - Inventory` |
| Returns team | `Ops - Returns` |
| Delivery team | `Ops - Delivery`, `Delivery Driver` as appropriate |
| Accounting | `Ops - Accounting` |
| Finance / collections | `Ops - Finance` |
| Directors | `Ops - Directors` |
| Purchasing | `Ops - Purchasing` |
| Purchasing lead | `Ops - Purchasing Lead` |

After real users are ready:

- disable/delete example users if they are not needed,
- keep team users only if they are used as assignment targets,
- do not leave known-password sample accounts enabled for real go-live.

#### 2. Run end-to-end smoke tests

Run these before first real transaction:

| Test | Expected result |
|---|---|
| Dispatch Case no-return flow | Order → pack → delivery → invoice/payment/debt closure works, stock entries correct |
| Dispatch Case return-expected flow | Delivery → return pickup → returns verification → restock/usage → invoice works, stock reconciliation correct |
| Discount approval | Discount creates Director approval task; rejected/approved behavior works |
| Delivery photo/handover gate | Delivery cannot complete without required photo/note if configured |
| Return drop-off photo gate | Return drop-off cannot complete without photo |
| Purchase Order approval | PO submit blocked until Director approval task is approved |
| PO re-approval | Editing approved draft PO resets approval to Pending |
| Purchase Receipt destination | PR to non-`Main - Inmed` is blocked |
| Purchase Receipt batch/expiry | Batch+expiry item cannot submit without batch/expiry |
| Purchase Invoice update stock | PI with `Update Stock = ON` is blocked |
| Debt threshold escalation | Customer over threshold creates Debt Collection task |
| Reorder governance | Unauthorized reorder threshold edits are blocked |
| Barcode scanner flow | REF + second GS1 barcode fills LOT/expiry/production/raw barcode correctly |

#### 3. Confirm barcode scanner deployment and test it

If not already verified live, run:

```powershell
.\deploy\barcode-gs1-deploy.ps1 -Mode Check
```

If fields/script are missing, deploy:

```powershell
.\deploy\barcode-gs1-deploy.ps1 -Mode Deploy
```

Then check again and do browser scanner test on Purchase Receipt.

#### 4. Confirm price lists for sales

Before real selling:

- Confirm `Standard Selling` has prices for all products that will be sold.
- If `Standard Selling` is incomplete, Sales Orders/Dispatch Cases may show wrong pricing or discount approval logic may behave incorrectly.

#### 5. Clean up risky existing records

Before go-live:

- Fix or cancel existing Tasks in `Working` / `Completed` with 0 or more than 1 assignee.
- Fill required fields on existing draft Purchase Orders:
  - `purchase_reason`,
  - `requested_by`.
- Delete harmless stray diagnostic record if desired:
  - `Workflow Action Master` record `TestAction888`.

---

### Priority 2 — should do before go-live, but may be formally deferred if needed

#### 1. Standard Buying prices

Needed for:

- gross profit reports,
- value-at-risk reports,
- more accurate valuation/profit analysis.

If missing:

- sales can still happen,
- profit/margin reports may show 0 or incomplete values.

#### 2. Reorder thresholds

Needed for purchasing/reorder planning.

For each relevant item, set Item Reorder rows:

- warehouse must be `Main - Inmed`,
- set `Reorder Level`,
- set `Reorder Qty`,
- fill `Reorder Change Reason` when saving.

Without this:

- `Stock Reorder` / reorder reports will not be useful.

#### 3. HS code and import tax rate

Needed for import duty costing automation.

Populate on imported items:

- `hs_code`,
- `import_tax_rate`.

Without this:

- Landed Cost Voucher import duty prefill cannot calculate correctly for those items.

#### 4. Manual saved views

Helpful for usability but not usually a blocker because workspace shortcuts exist.

Create views only if teams need them immediately.

---

### Priority 3 — can be done after go-live

- Item group hierarchy cleanup.
- Item naming convention cleanup.
- More Item Attribute values.
- Directors TV wallboard/kiosk user.
- Advanced dashboards and report order refinements.
- Server-side barcode validation hardening if client script proves insufficient.
- Internal/no-expiry barcode design for future expansion.
- Batch master auto-create/update logic, if later desired.

---

## 4. Exact Commands You May Need

### 4.1 Regenerate item tracking review

Only needed if item source data or rules change.

```powershell
$job = Start-Job -ScriptBlock {
    Set-Location "C:\Users\Levon\Windsurf\erpnext"
    python deploy\generate_item_tracking_review.py
}

if (Wait-Job $job -Timeout 60) {
    Receive-Job $job
    Remove-Job $job
} else {
    Stop-Job $job
    Remove-Job $job
    Write-Error "Timed out after 60 seconds"
}
```

Expected current result:

```text
BATCH_EXPIRY: 743
REF_ONLY: 2575
MANUAL_REVIEW: 0
HIGH risk: 0
```

### 4.2 Verify item tracking flags without changing anything

```powershell
$job = Start-Job -ScriptBlock {
    Set-Location "C:\Users\Levon\Windsurf\erpnext"
    python deploy\update_item_tracking_flags.py
}

if (Wait-Job $job -Timeout 60) {
    Receive-Job $job
    Remove-Job $job
} else {
    Stop-Job $job
    Remove-Job $job
    Write-Error "Timed out after 60 seconds"
}
```

Expected current result:

```text
Already OK: 3318
Would update: 0
Missing: 0
Ambiguous: 0
Errors: 0
```

### 4.3 Apply item tracking flags

This was already done. Do **not** run again unless a dry-run first shows intentional changes.

```powershell
python deploy\update_item_tracking_flags.py --apply
```

### 4.4 Barcode check/deploy/check

```powershell
.\deploy\barcode-gs1-deploy.ps1 -Mode Check
```

```powershell
.\deploy\barcode-gs1-deploy.ps1 -Mode Deploy
```

```powershell
.\deploy\barcode-gs1-deploy.ps1 -Mode Check
```

### 4.5 General deploy script pattern

Most deploy scripts support:

```powershell
.\deploy\docXXa-deploy.ps1 -Mode Check
.\deploy\docXXa-deploy.ps1 -Mode Deploy
.\deploy\docXXa-deploy.ps1 -Mode Verify
```

Not every script has `Verify`, so check the script parameters if unsure.

---

## 5. Go / No-Go Checklist

Use this as the final gate before first real transaction.

### Must be checked YES

- [ ] Real users created and assigned to roles.
- [ ] Example users disabled/deleted or formally retained only for testing.
- [ ] Role Permission Manager permissions manually verified for critical DocTypes.
- [x] Item tracking flags applied and verified.
- [ ] Standard Selling prices verified for all sellable items.
- [ ] Purchase Receipt barcode scanner deployed/verified if barcode receiving is part of go-live.
- [ ] End-to-end Dispatch Case no-return test passed.
- [ ] End-to-end Dispatch Case return-expected test passed.
- [ ] PO approval and PR/PI gates tested.
- [ ] Debt threshold escalation tested.
- [ ] Existing malformed Tasks cleaned or confirmed harmless.
- [ ] Existing draft Purchase Orders have required fields filled or are canceled.
- [ ] Team leads trained and agree to process rules.
- [ ] Readiness meeting held with Ops, Accounting, Purchasing, and Director.

### Can be YES or formally deferred

- [ ] Standard Buying prices populated.
- [ ] Reorder thresholds populated.
- [ ] HS codes/import tax rates populated.
- [ ] Saved views created.
- [ ] Directors TV wallboard created.
- [ ] Item naming/group cleanup completed.

---

## 6. Critical Operational Rules After Go-Live

These rules protect data integrity.

1. **All real stock movement for dispatch must follow the Dispatch Case flow.**
2. **Do not manually move stock from `Main - Inmed` directly to a client warehouse.**
3. **Use in-transit warehouses:**
   - delivery: `Main - Inmed` → `Delivery In-Transit - Inmed` → client location,
   - returns: client location → `Return Pickup In-Transit - Inmed` → `Returns - Inmed` → `Main - Inmed`.
4. **Do not enable invoice `Update Stock` for flows controlled by Dispatch Case/Purchase Receipt.**
5. **Do not bypass the Dispatch Case status/state machine.**
6. **Do not change item tracking flags after transactions begin unless fully reviewed.**
7. **Do not assign `System Manager` to daily operational staff.**
8. **For barcode receiving, scan one physical item at a time:** REF first, second barcode immediately after from the same package.
9. **For BATCH_EXPIRY products, preserve original LOT exactly in `batch_no` for traceability/returns.**
10. **Same item + same LOT + different expiry must remain separate receipt rows.**

---

## 7. If You Have Very Little Time

If quota ends or you need to continue alone, follow this order:

1. **Do not touch item tracking flags.** They are complete and verified.
2. **Assign real users/roles.** This is the biggest human go-live blocker.
3. **Run barcode check/deploy/check if Purchase Receipt barcode scanning is needed immediately.**
4. **Run the smoke tests from Section 3.** Fix only failures that block real process.
5. **Verify Standard Selling prices for products that will be sold first.**
6. **Populate required draft PO fields or cancel old drafts.**
7. **Hold go/no-go meeting.**
8. **Defer Standard Buying prices, reorder thresholds, saved views, and item naming cleanup only if management accepts the reporting limitations.**

---

## 8. Current Bottom Line

### Technically completed

- Core operational deployment scripts are deployed.
- Unified Dispatch Case flow is deployed.
- Reporting pack is deployed.
- Purchasing approval and receipt/invoice gates are deployed.
- Task governance is deployed.
- Role Permission Manager setup was completed manually.
- Item tracking flags are applied and verified.

### Not yet fully complete

- Real user/role assignment.
- Smoke testing and signoff.
- Barcode Purchase Receipt deployment/verification if not already live.
- Standard Buying prices and costing details.
- Reorder thresholds.
- Optional saved views and UI polish.

### Highest-risk remaining item

The highest-risk remaining work is **not code**. It is process validation:

```text
Run the real workflows end-to-end with the actual staff roles before first real transaction.
```

If those tests pass, the system is close to go-live.
