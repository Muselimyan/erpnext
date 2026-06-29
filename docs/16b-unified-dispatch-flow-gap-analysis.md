# Doc 16B — Unified Dispatch Flow: Gap Analysis (What Needs to Be Deployed)

## 0. Deployment Progress

| Date | Action | Result |
|---|---|---|
| 2026-05-11 | `doc16a-deploy.ps1` written — covers all 41 items | Script ready in `deploy/doc16a-deploy.ps1` |
| 2026-05-11 | Pre-deploy snapshot via `export.ps1` | deploy/ synced: 23 server scripts, 6 custom DocTypes, 62 custom fields, 14 task access policies |
| 2026-05-11 | `doc16a-deploy.ps1 -Mode Deploy` | ✅ **COMPLETE** — exit code 0, all items `exists: true` in verification |
| 2026-05-11 | Post-deploy snapshot via `export.ps1` | Custom fields: 74, Server scripts: 30, DocTypes: 10, Client scripts: 4, Users: 24, Roles: 60, Task Access Policies: 16 |
| 2026-06-01 | `Dispatch Case Item.unit_price` made optional | ✅ Live ERPNext field updated to `reqd = 0`; `doc16a-deploy.ps1` patched for future definitions |

**Legend for this document:**
- **✅ EXISTS** — already in prod
- **⚠️ UPDATE** — exists but needs modification
- **⏳ SCRIPTED** — covered in `doc16a-deploy.ps1`, not yet deployed to prod
- **❌ MISSING** — not yet scripted

---

## 1. Methodology

This document compares the current production state (as reflected in `deploy/`) against the requirements of Doc 16 and Doc 16A. Each item is classified as:

- **✅ EXISTS** — already in prod, no action needed
- **⚠️ UPDATE** — exists but needs to be modified
- **⏳ SCRIPTED** — covered in `doc16a-deploy.ps1`, pending `Deploy` run
- **❌ MISSING** — does not exist, must be created

Source files examined:
- `deploy/data/roles.csv` — roles in prod
- `deploy/data/users.csv` — users and team users in prod
- `deploy/data/task-access-policies.csv` — Task Access Policy records
- `deploy/schema/custom-fields.json` — custom fields (including Task fields)
- `deploy/schema/custom-doctypes.json` — custom DocTypes (6 total, Surgery Case family)
- `deploy/schema/server-scripts.json` — 23 server scripts in prod

**Deployment script:** `deploy/doc16a-deploy.ps1` (idempotent — safe to re-run)

---

## 2. Roles

| Role | Status | Notes |
|---|---|---|
| `Ops - Order Accepting` | ✅ EXISTS | |
| `Ops - Inventory` | ✅ EXISTS | |
| `Ops - Returns` | ✅ EXISTS | |
| `Ops - Delivery` | ✅ EXISTS | Used in prod; `Delivery Driver` also exists as distinct role |
| `Ops - Accounting` | ✅ EXISTS | |
| `Ops - Directors` | ✅ EXISTS | |
| `Delivery Driver` | ✅ EXISTS | |
| `Ops - Order Creating` | ✅ EXISTS | New role for Dispatch Case creation |
| `Ops - Finance` | ✅ EXISTS | New role for payment tasks |

---

## 3. Team Users

| User email | Full name | Role | Status | Notes |
|---|---|---|---|---|
| `order.team@example.com` | Order Team | `Ops - Order Accepting` | ✅ EXISTS | Covers Order Acceptance team |
| `inventory.team@example.com` | Inventory Team | `Ops - Inventory` | ✅ EXISTS | |
| `delivery.team@example.com` | Delivery Team | `Ops - Delivery` | ✅ EXISTS | |
| `returns.team@example.com` | Returns Team | `Ops - Returns` | ✅ EXISTS | |
| `accounting.team@example.com` | Accounting Team | `Ops - Accounting` | ✅ EXISTS | |
| `directors.team@example.com` | Directors Team | `Ops - Directors` | ✅ EXISTS | |
| `purchasing.team@example.com` | Purchasing Team | `Ops - Purchasing` | ✅ EXISTS | Not related to Doc 16 |
| Order Creation Team | `order.creation.team@example.com` | `Ops - Order Creating` | ✅ EXISTS | |
| Finance Team | `finance.team@example.com` | `Ops - Finance` | ✅ EXISTS | |

---

## 4. Task Kind Options

Current `task_kind` field options in prod:
```
Order entry
Pack / prepare items
Dispatch picking / hand-off
Delivery
Return to warehouse (aborted delivery / cancelled order)
Pickup Returns
Return drop-off at warehouse
Returns processing / verification
Invoice preparation / create invoice
Debt Collection
Distribute Payment
Discount Approval
Purchase Approval
Write-off Approval
```

| Option | Status |
|---|---|
| All 14 above | ✅ EXISTS |
| `Payment Received` | ✅ EXISTS |
| `Returns restocking` | ✅ EXISTS |

**Deployed:** `Task-task_kind` options updated with both new values.

---

## 5. Task Access Policies

| Policy | Status |
|---|---|
| `Order entry` | ✅ EXISTS |
| `Pack / prepare items` | ✅ EXISTS |
| `Dispatch picking / hand-off` | ✅ EXISTS |
| `Delivery` | ✅ EXISTS |
| `Pickup Returns` | ✅ EXISTS |
| `Return drop-off at warehouse` | ✅ EXISTS |
| `Returns processing / verification` | ✅ EXISTS |
| `Invoice preparation / create invoice` | ✅ EXISTS |
| `Debt Collection` | ✅ EXISTS |
| `Distribute Payment` | ✅ EXISTS |
| `Discount Approval` | ✅ EXISTS |
| `Purchase Approval` | ✅ EXISTS |
| `Write-off Approval` | ✅ EXISTS |
| `Return to warehouse (aborted delivery / cancelled order)` | ✅ EXISTS |
| `Payment Received` | ✅ EXISTS |
| `Returns restocking` | ✅ EXISTS |

---

## 6. Custom Fields on `Task`

| Fieldname | Label | Status | Notes |
|---|---|---|---|
| `task_kind` | Task Kind | ✅ EXISTS | Options need update (section 4) |
| `completed_at` | Completed At | ✅ EXISTS | |
| `task_access_policy` | Task Access Policy | ✅ EXISTS | |
| `approval_outcome` | Approval Outcome | ✅ EXISTS | Already used for Purchase Approval; reusable for Discount Approval |
| `approval_note` | Approval Note | ✅ EXISTS | |
| `purchase_order` | Purchase Order | ✅ EXISTS | |
| `sales_order` | Sales Order | ✅ EXISTS | |
| `sales_invoice` | Sales Invoice | ✅ EXISTS | |
| `customer` | Customer | ✅ EXISTS | |
| `dispatch_group_id` | Dispatch Group ID | ✅ EXISTS | |
| `surgery_case` | Surgery Case | ✅ EXISTS | Legacy link, kept for old cases |
| `warehouse_pickup_photo` | Warehouse Pickup Photo | ✅ EXISTS | Reusable as `delivery_photo` for Delivery task "Delivered" state |
| `warehouse_dropoff_photo` | Warehouse Drop-off Photo | ✅ EXISTS | Reusable as return drop-off photo for Return Pickup "Returned to Warehouse" state |
| `driver_handover_note` | Driver Handover Note | ✅ EXISTS | Reusable as handover note in Delivery task |
| `payment_entry` | Payment Entry | ✅ EXISTS | |
| `current_debt_amd` | Current Debt (AMD) | ✅ EXISTS | Used by old debt monitoring script |
| `debt_threshold_amd` | Debt Threshold (AMD) | ✅ EXISTS | Used by old debt monitoring script |
| `dispatch_case` | Dispatch Case | ✅ EXISTS | Link → `Dispatch Case` |
| `delivery_status` | Delivery Status | ✅ EXISTS | Select: `Todo / Picked Up / Delivered` |
| `pickup_status` | Pickup Status | ✅ EXISTS | Select: `Todo / Picked Up / Returned to Warehouse` |
| `return_pickup_driver` | Return Pickup Driver | ✅ EXISTS | Link → `User` |
| `scheduled_return_date` | Scheduled Return Date | ✅ EXISTS | Date |
| `new_payment_amount` | New Payment Amount | ✅ EXISTS | Currency — for recording payments on Debt Collection task |
| `payment_method_dc` | Payment Method | ✅ EXISTS | Select: `Cash / Bank Transfer / Card` |
| `payment_reference_dc` | Payment Reference | ✅ EXISTS | Data |
| `total_outstanding` | Total Outstanding | ✅ EXISTS | Currency, Read Only |
| `available_advance_credit` | Available Advance Credit | ✅ EXISTS | Currency, Read Only |
| `open_invoices` | Open Invoices | ✅ EXISTS | Table → `Debt Collection Invoice` child DocType |
| `payment_history` | Payment History | ✅ EXISTS | Table → `Debt Collection Payment` child DocType |

**Note on reuse:** `warehouse_pickup_photo`, `warehouse_dropoff_photo`, and `driver_handover_note` already exist and can be reused in the new multi-state task logic — no new fields needed for these. The gate server scripts will be updated to check them at the new state transition points.

---

## 7. Custom DocTypes

Current custom DocTypes in prod (6 total, all Surgery Case family):

| DocType | Status | Notes |
|---|---|---|
| `Surgery Case` | ✅ EXISTS | Old coordinator record — keep for now, do not remove |
| `Surgery Case Item` | ✅ EXISTS | Old child table |
| `Surgery Case Serial Exception` | ✅ EXISTS | Old child table |
| *(3 more Surgery Case related)* | ✅ EXISTS | Verified from custom-doctypes.json count=6 |
| `Dispatch Case` | ✅ EXISTS | New parent coordinator DocType (autoname `DC-.YYYY.-.#####`, submittable) |
| `Dispatch Case Item` | ✅ EXISTS | New child table for Dispatch Case; `unit_price` is optional |
| `Debt Collection Invoice` | ✅ EXISTS | Child table for open invoices on Debt Collection task |
| `Debt Collection Payment` | ✅ EXISTS | Child table for payment history on Debt Collection task |

---

## 8. Server Scripts

### 8.1 Existing scripts — status

| Script name | Status | Action needed |
|---|---|---|
| `Task-before-save-policy` | ✅ EXISTS | Updated: adds `Ops - Order Creating`, `Ops - Finance`, `Returns restocking`, `Payment Received`; skips old photo gates for dispatch-case tasks |
| `Customer-before-save-governance` | ✅ KEEP | No changes needed |
| `StockEntry-before-submit-fefo` | ✅ KEEP | No changes needed |
| `Task-purchase-approval-writeback` | ✅ KEEP | No changes needed |
| `Purchase Order-before-submit-director-approval` | ✅ KEEP | No changes needed |
| `Purchase Order-before-save-clear-approval` | ✅ KEEP | No changes needed |
| `Purchase Receipt-before-submit-main-inmed-expiry` | ✅ KEEP | No changes needed |
| `Purchase Invoice-before-submit-no-update-stock` | ✅ KEEP | No changes needed |
| `Purchase Order-validate-one-supplier` | ✅ KEEP | No changes needed |
| `Item-before-save-reorder-change-reason` | ✅ KEEP | No changes needed |
| `Item-before-save-reorder-governance` | ✅ KEEP | No changes needed |
| `Delivery Note-before-submit-delivery-gate` | ✅ KEEP | Old standard sale flow — keep until fully retired |
| `Task-before-save-discount-approval-writeback` | ✅ KEEP | Old Sales Order discount approval — keep for old flow |
| `Stock Entry-before-submit-dispatch-gate` | ✅ KEEP | Old Surgery Case SE gate — keep for old cases |
| `Stock Entry-before-save-no-client-wh` | ✅ KEEP | Still relevant — keep |
| `Task-before-save-return-dropoff-photo` | ✅ KEEP | Old photo enforcement kept for non-dispatch-case tasks; dispatch-case tasks handled by `Task-before-save-dispatch-gates` |
| `Sales Order-before-save-discount-approval` | ✅ KEEP | Old Sales Order flow — keep until retired |
| `Scheduled-debt-collection` | ✅ KEEP | Still monitors debt thresholds for old flow — keep |
| `Payment Entry-after-submit-distribute-payment` | ✅ KEEP | Old payment distribution — review for overlap with new flow |
| `Surgery-Set-Type-validate-readiness` | ✅ KEEP | Still valid — Collection Sets used as templates |
| `Surgery-Case-before-save` | ✅ KEEP | Old Surgery Case scripts — keep for existing cases in flight |
| *(2 remaining scripts)* | ✅ KEEP | Old flow scripts from doc09b |

### 8.2 New scripts required

| Script name | Trigger | Purpose |
|---|---|---|
| `Dispatch-Case-before-save` | Dispatch Case → Before Save | ✅ EXISTS — Auto-compute `used_qty`; detect discount → `Awaiting Approval` |
| `Dispatch-Case-after-save` | Dispatch Case → After Save | ✅ EXISTS — Create `Discount Approval` task if discount detected |
| `Dispatch-Case-before-submit` | Dispatch Case → Before Submit | ✅ EXISTS — Validate items; create Pack task |
| `Task-before-save-dispatch-gates` | Task → Before Save | ✅ EXISTS — Photo/serial/batch/qty/invoice gates for all dispatch task kinds |
| `Task-after-save-dispatch-flow` | Task → After Save | ✅ EXISTS — Main orchestrator: SEs + next-task creation for all status transitions |
| `Task-before-save-payment-recording` | Task → Before Save | ✅ EXISTS — FIFO payment allocation, Payment Entry, Distribute Payment task |
| `Task-after-save-advance-payment` | Task → After Save | ✅ EXISTS — Advance Payment Entry on Payment Received task completion |

---

## 9. Client Scripts

| Script | Status |
|---|---|
| Dispatch Case form — `Load from Template` (auto-fill items from Collection Set on field change) | ✅ EXISTS |

---

## 10. Workspace Shortcuts

Originally not audited in detail (workspaces.json is large). On 2026-06-01, the confirmed task shortcuts were deployed in a clean workspace named `Dispatch - Task Queues` by `doc15e-deploy.ps1`.

| Shortcut label | Filter |
|---|---|
| VIEW: Pack Tasks | `task_kind = Pack / prepare items` |
| VIEW: Delivery Tasks | `task_kind = Delivery` |
| VIEW: Return Pickup Tasks | `task_kind = Pickup Returns` |
| VIEW: Returns Inspection Tasks | `task_kind = Returns processing / verification` |
| VIEW: Restock Tasks | `task_kind = Returns restocking` |
| VIEW: Invoice Tasks | `task_kind = Invoice preparation / create invoice` |
| VIEW: Debt Collection Tasks | `task_kind = Debt Collection` |
| VIEW: Payment Received Tasks | `task_kind = Payment Received` |
| VIEW: Distribute Payment Tasks | `task_kind = Distribute Payment` |
| VIEW: All Dispatch Cases | DocType: Dispatch Case |

These shortcuts now exist in `Dispatch - Task Queues`; users should smoke test that each shortcut opens the expected filtered list.

---

## 11. Deployment Order

Items must be deployed in this order due to dependencies:

```
Step 1 — Roles and Team Users
  1a. Create role: Ops - Order Creating
  1b. Create role: Ops - Finance
  1c. Create user: order.creation.team@example.com  (role: Ops - Order Creating)
  1d. Create user: finance.team@example.com  (role: Ops - Finance)

Step 2 — Task Kind options (update existing custom field)
  2a. Update task_kind options: append Payment Received, Returns restocking

Step 3 — Task Access Policies (2 new records)
  3a. Create: Payment Received
  3b. Create: Returns restocking

Step 4 — New child DocTypes (no dependencies)
  4a. Create: Dispatch Case Item
  4b. Create: Debt Collection Invoice
  4c. Create: Debt Collection Payment

Step 5 — New custom fields on Task (depends on Step 4 for child table fields)
  5a. dispatch_case (Link)
  5b. delivery_status (Select)
  5c. pickup_status (Select)
  5d. return_pickup_driver (Link)
  5e. scheduled_return_date (Date)
  5f. new_payment_amount (Currency)
  5g. payment_method (Select)
  5h. payment_reference (Data)
  5i. total_outstanding (Currency, Read Only)
  5j. available_advance_credit (Currency, Read Only)
  5k. open_invoices (Table → Debt Collection Invoice)
  5l. payment_history (Table → Debt Collection Payment)

Step 6 — Dispatch Case parent DocType (depends on Step 4)
  6a. Create: Dispatch Case

Step 7 — Server script updates (depends on Steps 1-6)
  7a. UPDATE: Task-before-save-policy  (add new roles and kinds)
  7b. UPDATE: Task-before-save-return-dropoff-photo  (or fold into 7d)

Step 8 — New server scripts (depends on Steps 1-6)
  8a. CREATE: Dispatch-Case-before-save
  8b. CREATE: Dispatch-Case-before-submit
  8c. CREATE: Task-before-save-dispatch-gates
  8d. CREATE: Task-after-save-dispatch-flow
  8e. CREATE: Task-after-save-payment-recording
  8f. CREATE: Task-after-save-advance-payment

Step 9 — Client Script
  9a. CREATE: Dispatch Case form — Load from Template

Step 10 — Workspace shortcuts
  10a. Add Dispatch Case inbox views to relevant workspaces

Step 11 — Permissions
  11a. Set Dispatch Case permissions per role (Doc 16A section 8)
  11b. Set Task Access Policy User Permissions for Ops - Order Creating and Ops - Finance users
```

---

## 12. Summary Counts

| Category | Before Deploy | After Deploy (prod snapshot 2026-05-11) | Remaining |
|---|---|---|---|
| Roles | 58 | **60** (+2) | 0 |
| Team Users | 22 | **24** (+2) | 0 |
| Task Kind options | 14 | **16** (+2) | 0 |
| Task Access Policies | 14 | **16** (+2) | 0 |
| Task custom fields | 62 total | **74 total** (+12) | 0 |
| Custom DocTypes | 6 | **10** (+4) | 0 |
| Server Scripts | 23 | **30** (+7 new + 1 updated) | 0 |
| Client Scripts | 3 | **4** (+1) | 0 |
| Workspace shortcuts | partial | `Dispatch - Task Queues` deployed 2026-06-01 | 0 core shortcuts |

**✅ All 41 items deployed successfully.**  
**Remaining gap: no core implementation gap; end-to-end smoke tests are still required before final sign-off.**
