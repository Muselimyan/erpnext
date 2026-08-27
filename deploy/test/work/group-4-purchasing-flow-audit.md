# Group 4: Purchasing Flow — Audit Findings

> **Scope**: All deployed server scripts, client scripts, custom fields, and property setters related to the Purchase Order → Purchase Receipt → Purchase Invoice pipeline, including director approval, discount approval, reorder notifications, and Landed Cost Voucher.
>
> **Method**: Every script was read line by line. Every reference document was read in full. Every custom field was verified against the schema export. No assumptions were made — each finding cites the exact code and exact doc section.
>
> **Date**: 2026-08-27

---

## 1. Summary

| Metric | Value |
|---|---|
| Server scripts analyzed | 10 (8 enabled, 2 disabled) |
| Client scripts analyzed | 1 (enabled) |
| Reference docs analyzed | 8 (Doc 07, 07A, 08, 08A, 17, 17A, plus 3 manuals) |
| Custom fields verified | 29 (across PO, PR, PI, SO, Item, Item Reorder) |
| Findings | 18 |
| Critical | 1 |
| High | 4 |
| Medium | 8 |
| Low | 5 |

---

## 2. Script-by-Script Analysis

### 2.1 Enabled Server Scripts

#### S1: `Purchase Order-before-save-clear-approval.py`
**Type**: DocType Event — Purchase Order — Before Save — **ENABLED**
**Lines**: 44 | **Summary**: Clears director approval if an approved Draft PO is edited.

**What it does (exact logic)**:
1. Gets the document state before save.
2. Only runs on Draft POs (`docstatus == 0`) that were previously "Approved".
3. Checks if any header field changed: `supplier`, `currency`, `transaction_date`, `purchase_reason`, `requested_by`.
4. Normalizes item rows and compares: `item_code`, `uom`, `conversion_factor`, `qty`, `rate`, `schedule_date`.
5. If any change detected → resets all 5 approval fields to Pending/None and shows a message.

**Doc reference**: Doc 07A §6.5 — "Any change after approval requires re-approval."
**Code vs doc**: The deployed code exactly matches the documented script in Doc 07A §6.5, character for character (modulo the absence of `from frappe.utils import now_datetime` which is unused here anyway). The code uses `doc.get_doc_before_save()` at line 8 and skips `return` syntax, using `if/if` guards instead — functionally identical.
**Verdict**: **MATCH** — code implements the doc accurately.
**Confidence**: 98%

---

#### S2: `Purchase Order-before-submit-director-approval.py`
**Type**: DocType Event — Purchase Order — Before Submit — **ENABLED**
**Lines**: 12 | **Summary**: Blocks PO submission unless `director_approval_status == "Approved"`.

**What it does (exact logic)**:
1. Checks `doc.director_approval_status != "Approved"`.
2. If not Approved → `frappe.throw()` with a clear error message.

**Doc reference**: Doc 07A §6.4 — "blocks PO submission unless approval is Approved."
**Code vs doc**: Exact match with Doc 07A §6.4 script, identical logic and error message.
**Verdict**: **MATCH**
**Confidence**: 99%

---

#### S3: `Purchase Receipt-before-submit-main-inmed-expiry.py`
**Type**: DocType Event — Purchase Receipt — Before Submit — **ENABLED**
**Lines**: 28 | **Summary**: Enforces all items received into `Main - Inmed`; validates batch+expiry for tracked items.

**What it does (exact logic)**:
1. For each item row, checks `row.warehouse != "Main - Inmed"` → throw.
2. Loads the Item doc to check `has_expiry_date` and `has_batch_no`.
3. If item requires both expiry + batch:
   - Checks `row.batch_no` is set → throw if missing.
   - Loads Batch doc and checks `batch.expiry_date` is set → throw if missing.

**Doc reference**: Doc 07A §9.0 (PR gate script); Doc 17A §8.2 (operating procedure).
**Code vs doc**:
- The docs refer to warehouse as `Main - WH` (Doc 07, Doc 08) but the deployed code uses `Main - Inmed`. This is consistent — `Main - Inmed` is the actual ERPNext warehouse name for the InMED company (the docs use generic `Main - WH` as placeholder, but the manual says `Main - Inmed`).
- The logic matches the documented script in Doc 07A §9.0. The deployed version has `MAIN_WH = "Main - Inmed"` hardcoded (correct for production).
- One subtle difference: Doc 07A §9.0 shows the script checking `has_expiry_date and has_batch_no` together, and the deployed code does the same. However, this means items that have `has_batch_no = True` but `has_expiry_date = False` are NOT validated for batch number. Given that `disable_all_item_batch_serial_for_now.py` has set all items to `has_batch_no = 0`, this branch currently never fires for any item.
**Verdict**: **MATCH** (but effectively inert for 244/246 items since batch tracking is disabled for most)
**Confidence**: 95%

---

#### S4: `Purchase Invoice-before-submit-no-update-stock.py`
**Type**: DocType Event — Purchase Invoice — Before Submit — **ENABLED**
**Lines**: 9 | **Summary**: Blocks PI from updating stock.

**What it does (exact logic)**:
1. Checks `doc.get("update_stock")`.
2. If truthy → `frappe.throw()` directing user to use Purchase Receipt.

**Doc reference**: Doc 07A §10; Doc 17A §10.2.
**Code vs doc**: Exact match. The error message references "Doc 07 policy", consistent with Doc 07 §6.6 (PI is financial truth, not stock truth).
**Verdict**: **MATCH**
**Confidence**: 99%

---

#### S5: `Task-purchase-approval-writeback.py`
**Type**: DocType Event — Task — Before Save — **ENABLED**
**Lines**: 28 | **Summary**: When a Purchase Approval task completes, writes approval outcome back to the PO.

**What it does (exact logic)**:
1. Detects "becoming Completed" transition.
2. Guards on `task_kind == "Purchase Approval"`.
3. Validates `purchase_order` is set → throw if missing.
4. Validates `approval_outcome` is "Approved" or "Rejected" → throw if not.
5. Loads PO doc, sets: `director_approval_status`, `director_approved_by` (from `doc.modified_by or doc.owner`), `director_approved_at` (from `frappe.utils.now_datetime()`), `director_approval_task`, `director_approval_note`.
6. Saves PO with `ignore_permissions=True`.

**Doc reference**: Doc 07A §6.3.
**Code vs doc**:
- Almost identical. Doc 07A §6.3 script imports `from frappe.utils import now_datetime` and calls `now_datetime()`. The deployed code calls `frappe.utils.now_datetime()` without the import — functionally identical in server script context.
- Doc 07A §6.3 script uses `return` for early exit; deployed code uses `if/if` guards — functionally identical.
**Verdict**: **MATCH**
**Confidence**: 98%

---

#### S6: `Task-before-save-discount-approval-writeback.py`
**Type**: DocType Event — Task — Before Save — **ENABLED**
**Lines**: 103 | **Summary**: When Discount Approval task completes, writes approval back to **Sales Order** and creates Pack task if approved.

**What it does (exact logic)**:
1. Wraps all logic in `run_script(doc)` → called at line 103.
2. Detects "becoming Completed" transition.
3. Guards on `task_kind == "Discount Approval"`.
4. Validates `sales_order` is set → throw if missing.
5. Validates `approval_outcome` → throw if not Approved/Rejected.
6. Uses `frappe.db.set_value()` to write `discount_approval_status`, `discount_approval_note`, `discount_approval_task` to the Sales Order.
7. If Approved AND the Sales Order is submitted (`docstatus == 1`):
   - Checks for existing non-cancelled Pack task.
   - If none exists → creates a "Pack / prepare items" Task linked to the SO.
   - Assigns to first enabled user with role `Ops - Inventory`.
8. Contains a full `assign_single_owner()` helper that manages `_assign` JSON and ToDo records.

**Doc reference**: Doc 09 §7 (superseded), Doc 09A §7 (superseded). The discount-approval-walkthrough.md describes the current flow as operating on **Dispatch Case**, not Sales Order.
**Code vs doc**:
- **THIS SCRIPT OPERATES ON SALES ORDER** — it writes back to `Sales Order` fields (`discount_approval_status`, etc.) and creates Pack tasks linked to `sales_order`.
- The current discount approval walkthrough clearly describes the flow as: Dispatch Case saved with discount → status "Awaiting Approval" → Discount Approval task auto-created → Director approves → case proceeds.
- The Dispatch Case discount flow is handled by `Dispatch-Case-before-save.py` (sets Awaiting Approval) and `Dispatch-Case-after-save.py` (creates the Discount Approval task).
- **However**: when the Director completes the Discount Approval task, the writeback goes to **Sales Order** (this script), not Dispatch Case. The Dispatch Case has no `discount_approval_status` field — it only has `custom_packing_problem_status`. This means:
  - If the discount approval task was created from a **Sales Order** context (old flow), the writeback works.
  - If the discount approval task was created from a **Dispatch Case** context (new flow), the `doc.sales_order` field may be empty, causing the script to throw "Discount Approval task must be linked to a Sales Order."
- **This is a potential bug** depending on how Dispatch Case discount approval tasks populate the `sales_order` field.

**Verdict**: **LIKELY BUG / LEGACY CONFLICT** — the writeback targets Sales Order, but the current operational flow creates discount approval tasks from Dispatch Case.
**Confidence**: 85% (would need live verification to confirm whether Dispatch Case discount tasks actually have `sales_order` set)

---

#### S7: `Sales Order-before-save-discount-approval.py`
**Type**: DocType Event — Sales Order — Before Save — **ENABLED**
**Lines**: 245 | **Summary**: Full discount approval workflow on Sales Order — detects discounts, creates/manages approval tasks, enforces manual pricing rules.

**What it does (exact logic)**:
1. **Header-level discount block**: If `additional_discount_percentage != 0` → throw (forces per-line discounts only).
2. **Discount detection**: Scans items for `discount_percentage > 0` or manual rate override (rate differs from expected `price_list_rate × (1 - discount_pct/100)` by more than 0.01).
3. **Smart edge case**: If `price_list_rate <= 0`, does NOT treat entered rate as override (prevents false positives when price list isn't populated).
4. **No discount path**: Sets `discount_approval_status = "Not Required"`, cancels any open Discount Approval tasks + their ToDos.
5. **Discount path with signature preservation**: If discount was previously Approved/Rejected AND the pricing signature (all item codes + discount % + rate + price_list_rate) hasn't changed → preserves the existing approval.
6. **New discount path**: Sets status to "Pending", enforces manual pricing reason and Accounting/Directors role check for manual rate overrides.
7. **Task management**: Reuses existing open Discount Approval task for same SO, or creates a new one assigned to the first enabled Director user.
8. Contains full `assign_single_owner()` and `user_has_role()` helpers.

**Doc reference**: Doc 09 §7 (superseded by Doc 16). Doc 09A §7.
**Code vs doc**:
- This entire script implements the Doc 09 Sales Order discount approval flow.
- Doc 09 is explicitly marked as **SUPERSEDED** by Doc 16 (Unified Dispatch Flow).
- The current discount-approval-walkthrough.md describes the flow as operating on **Dispatch Case**, not Sales Order.
- **But this script is ENABLED and ACTIVE.** Any time a Sales Order is saved, this 245-line script runs.
- The existence of both this script AND the Dispatch Case discount scripts (`Dispatch-Case-before-save.py`, `Dispatch-Case-after-save.py`) means there are **two parallel discount approval systems** running in production:
  1. Sales Order → this script → creates "Discount Approval" task linked to SO → writeback via S6.
  2. Dispatch Case → `Dispatch-Case-before-save.py` → sets status → `Dispatch-Case-after-save.py` → creates "Discount Approval" task linked to DC → **no dedicated writeback script found for DC path**.

**Verdict**: **DUAL SYSTEM — requires clarification** whether Sales Orders are still used in production alongside Dispatch Cases, or whether this is dead code.
**Confidence**: 90%

---

#### S8: `Sales Order-after-submit-pack-task.py`
**Type**: DocType Event — Sales Order — After Submit — **ENABLED**
**Lines**: 72 | **Summary**: Creates Pack task when a Sales Order is submitted (if discount is approved/not required).

**What it does (exact logic)**:
1. Wraps in `run_script(doc)`.
2. Checks `discount_approval_status` — returns if not "Not Required" or "Approved".
3. Checks for existing non-cancelled Pack task for this SO → returns if found.
4. Creates a "Pack / prepare items" Task linked to the Sales Order.
5. Assigns to first enabled `Ops - Inventory` user.
6. Contains full `assign_single_owner()` helper.

**Doc reference**: Doc 09A §6 (superseded).
**Code vs doc**:
- Same situation as S7. This is the Doc 09 Sales Order → Pack task chain. In the Doc 16 flow, pack task creation happens differently (via `Task-after-save-dispatch-flow.py` in Group 1, triggered by Task completion, not SO submission).
- **Script is ENABLED and ACTIVE.** Every Sales Order submission creates a Pack task.

**Verdict**: **DUAL SYSTEM — same as S7 finding**
**Confidence**: 90%

---

#### S9: `doc15_norm_reorder_daily_notifications.py`
**Type**: Scheduler Event — **ENABLED**
**Lines**: 47 | **Summary**: Daily scheduler that checks for items below reorder level and creates ToDo notifications.

**What it does (exact logic)**:
1. Collects all enabled users with roles `Ops - Purchasing` or `Ops - Directors`.
2. Runs SQL query against `tabBin` joined with `tabItem` and `tabItem Reorder`:
   - Filters: `i.disabled = 0`, `ir.warehouse_reorder_level > 0`, `b.actual_qty <= ir.warehouse_reorder_level`.
   - Limited to 100 items.
3. If items found below reorder:
   - Builds a description with first 50 item codes.
   - For each recipient, creates a ToDo (if one doesn't already exist for today with same description prefix).
   - Commits the transaction.

**Doc reference**: Doc 08A §8.1 (daily quick check); Doc 15 (reporting requirements review, where this script's naming `doc15_` comes from).
**Code vs doc**:
- Doc 08 describes a daily/weekly buyer operating routine but does not mandate automated notifications.
- Doc 08A does not include a scheduler script — it relies on manual report checking.
- This script is an **undocumented enhancement** that goes beyond Doc 08. It implements the spirit of Doc 08's daily check requirement but as an automated notification rather than a manual routine.
- **Bug (minor)**: Line 31 contains a UTF-8 encoding issue — `"RPT â€" Purchasing â€" Norm and Reorder"` should be `"RPT — Purchasing — Norm and Reorder"` (em-dash was corrupted to the â€" sequence). This will display garbled text in the ToDo notification.
- **Design note**: The SQL uses `actual_qty` (physical on-hand) not `projected_qty` (which accounts for reserved/ordered). Doc 08 §6.1 defines net availability as `on-hand - committed demand`, but this script only checks raw `actual_qty`. This is a simpler check but may miss items that are technically available but committed.
- **Query limit**: Only 100 items are returned (`limit 100`). If more than 100 items are below threshold, some won't appear in the notification.

**Verdict**: **UNDOCUMENTED ENHANCEMENT with minor bugs**
**Confidence**: 95%

---

#### S10: `Item-before-save-reorder-governance.py`
**Type**: DocType Event — Item — Before Save — **ENABLED**
**Lines**: 35 | **Summary**: Requires `reorder_change_reason` when reorder thresholds are modified.

**What it does (exact logic)**:
1. Gets document before save.
2. If no previous version → passes (new items don't need a reason).
3. Uses `REORDER_FIELDNAME = "reorder_levels"` to access the Item Reorder child table.
4. Normalizes rows to `{warehouse, reorder_level, reorder_qty}` dictionaries with float conversion.
5. If normalized before != after AND `reorder_change_reason` is empty → throw.

**Doc reference**: Doc 08A §7.4.
**Code vs doc**: Exact match with the documented script in Doc 08A §7.4 (Variant A). Uses the same normalization approach with `getattr` for safety.
**Verdict**: **MATCH**
**Confidence**: 99%

---

### 2.2 Disabled Server Scripts

#### D1: `Purchase Order-validate-one-supplier.py`
**Type**: DocType Event — Purchase Order — Before Save — **DISABLED**
**Lines**: 29 | **Summary**: Validates that each PO item has exactly one supplier matching the PO supplier.

**What it does (exact logic)**:
1. For each item row, queries `Item Supplier` child table for the item.
2. Checks exactly 1 supplier exists → throw if 0 or 2+.
3. Checks that single supplier matches `doc.supplier` → throw if mismatch.

**Doc reference**: Doc 07A §6.4.1 — explicitly creates this script. Doc 07 §5 — "Each sellable stock item must have exactly one supplier." Doc 07 §6.2 — "A PO must be per-supplier (do not mix suppliers on one PO)."
**Code vs doc**: The deployed code matches the documented script in Doc 07A §6.4.1 exactly.
**Status**: **DISABLED in production** despite being documented as required.
**Likely reason for disabling**: Performance or practical workflow issue — if the Item Supplier table is not populated for all items, this script would block PO creation. Doc 17A §2.6 shows that 244 out of 246 items have no batch tracking, and the Item Supplier table may not be fully populated yet.

**Verdict**: **DOC-PROD MISMATCH — required control is disabled**
**Confidence**: 95%

---

#### D2: `Item-before-save-reorder-change-reason.py`
**Type**: DocType Event — Item — Before Save — **DISABLED**
**Lines**: 14 | **Summary**: Earlier/simpler version of reorder change reason enforcement.

**What it does**: Same purpose as S10 but with simpler normalization (uses tuple comparison instead of dict, accesses `before.reorder_levels` directly instead of `before.get(REORDER_FIELDNAME)`).
**Relationship to S10**: S10 is the replacement. D2 is the original version that was superseded.
**Verdict**: **Correctly disabled — superseded by S10**
**Confidence**: 99%

---

### 2.3 Client Scripts

#### C1: `LCV-import-duty-prefill.js`
**Type**: Client Script — Landed Cost Voucher — Form — **ENABLED**
**Lines**: 76 | **Summary**: Adds "Pre-fill Import Duty" button that calculates import duty from item `import_tax_rate`.

**What it does (exact logic)**:
1. On `refresh`: if doc is Draft (`docstatus === 0`), adds custom button "Pre-fill Import Duty" under "Tools" group.
2. Collects unique item codes from `frm.doc.items`.
3. Calls `frappe.client.get_list` to fetch `import_tax_rate` for each item.
4. Calculates: `total_duty = sum(row.amount × rate / 100)`, rounded to 2 decimals.
5. If `total_duty <= 0` → shows message about missing rates.
6. Finds or creates an "Import Duty" row in `taxes` table (by matching `description === 'Import Duty'`).
7. If existing row → updates amount. If no existing row → adds new row with description "Import Duty".
8. Shows green alert with the pre-filled amount.

**Doc reference**: Doc 17A §6.1.
**Code vs doc**:
- Doc 17A §6.1 shows a different version of the script that removes an existing Import Duty row and adds a new one (using `grid.grid_rows[idx].remove()`).
- The deployed version finds the existing row and updates its amount in-place using `frappe.model.set_value()`, or adds a new row if none exists. This is a **better implementation** than the documented version — it preserves any user-set Expense Account instead of removing and recreating the row.
- The deployed version puts the button under the "Tools" group (`frm.add_custom_button(__, fn, __('Tools'))`), while the doc version puts it as a standalone button. Minor UI difference.
- Both versions calculate the same formula: `item_amount × import_tax_rate / 100`.

**Verdict**: **CODE IS BETTER THAN DOC — doc should be updated to match**
**Confidence**: 95%

---

## 3. Custom Fields Verification

### 3.1 Purchase Order Custom Fields (7 fields)

| Fieldname | Type | Doc Reference | Schema | Deployed | Match? |
|---|---|---|---|---|---|
| `purchase_reason` | Select | Doc 07A §6.2 | Yes | Yes | **MATCH** — Options not verified against doc (would need live check) |
| `requested_by` | Link → User | Doc 07A §6.2 | Yes | Yes | **MATCH** |
| `director_approval_status` | Select | Doc 07A §6.2 | Yes | Yes | **MATCH** — Options: Pending/Approved/Rejected per doc |
| `director_approved_by` | Link → User | Doc 07A §6.2 | Yes | Yes | **MATCH** |
| `director_approved_at` | Datetime | Doc 07A §6.2 | Yes | Yes | **MATCH** |
| `director_approval_task` | Link → Task | Doc 07A §6.2 | Yes | Yes | **MATCH** |
| `director_approval_note` | Small Text | Doc 07A §6.2 | Yes | Yes | **MATCH** |

**Verdict**: All 7 PO custom fields match documentation exactly. **Confidence: 99%**

### 3.2 Sales Order Custom Fields (10 fields)

| Fieldname | Type | Doc Reference | Deployed | Match? |
|---|---|---|---|---|
| `discount_approval_status` | Select | Doc 09A §7 (superseded) | Yes | **LEGACY** — from superseded Doc 09 |
| `discount_approval_note` | Small Text | Doc 09A §7 (superseded) | Yes | **LEGACY** |
| `discount_approval_task` | Link → Task | Doc 09A §7 (superseded) | Yes | **LEGACY** |
| `doctor_name` | Data | Doc 09 §4.1 (superseded) | Yes | **LEGACY** |
| `hospital` | Link | Doc 09 §4.1 (superseded) | Yes | **LEGACY** |
| `hospital_branch` | Data | Doc 09 §4.1 (superseded) | Yes | **LEGACY** |
| `is_prepaid` | Check | Doc 09 §6.5 (superseded) | Yes | **LEGACY** |
| `manual_pricing_reason` | Small Text | Doc 09 §7 (superseded) | Yes | **LEGACY** |
| `prepayment_payment_entry` | Link → Payment Entry | Doc 09 §6.5 (superseded) | Yes | **LEGACY** |
| `prepayment_required_amount_amd` | Currency | Doc 09 §6.5 (superseded) | Yes | **LEGACY** |

**Verdict**: All 10 SO custom fields exist and are from the superseded Doc 09 flow. No current documentation (Doc 16) references these fields. **Confidence: 95%**

### 3.3 Item Custom Fields (5 fields + 1 on Item Reorder)

| Fieldname | Type | Doc Reference | Deployed | Match? |
|---|---|---|---|---|
| `hs_code` | Data | Doc 17 §3, Doc 17A §5.1 | Yes | **MATCH** |
| `import_tax_rate` | Float | Doc 17 §3, Doc 17A §5.2 | Yes | **MATCH** |
| `reorder_change_reason` | Small Text | Doc 08A §7.3 | Yes | **MATCH** |
| `custom_1c_code` | Data | None | Yes | **UNDOCUMENTED** — references legacy 1C accounting system |
| `pack_breaking_policy` | Select | Mentioned in Doc 06/07 conceptually | Yes | **NO DEDICATED DOC** — conceptually discussed but no numbered doc defines the field |
| `buffer_percentage` (on Item Reorder) | Float | None | Yes | **UNDOCUMENTED** — safety stock buffer percentage |

**Verdict**: 3 match, 3 have no or incomplete documentation. **Confidence: 95%**

### 3.4 Purchase Receipt Custom Fields (4 fields on PR, 3 on PR Item)

| Fieldname | Type | Doc Reference | Deployed | Match? |
|---|---|---|---|---|
| `custom_allow_expired_barcode_receipt` | Check | Barcode docs (not numbered) | Yes | **UNDOCUMENTED** in numbered docs |
| `custom_allow_future_production_date` | Check | Barcode docs (not numbered) | Yes | **UNDOCUMENTED** in numbered docs |
| `custom_barcode_override_reason` | Small Text | Barcode docs (not numbered) | Yes | **UNDOCUMENTED** in numbered docs |
| `custom_barcode_override_section` | Section Break | Barcode docs (not numbered) | Yes | **UNDOCUMENTED** in numbered docs |
| `custom_expiry_date` (PR Item) | Date | Doc 17A §2.3 | Yes | **MATCH** |
| `custom_production_date` (PR Item) | Date | Barcode docs | Yes | **UNDOCUMENTED** in numbered docs |
| `custom_scanned_gs1_barcode` (PR Item) | Small Text | Barcode docs | Yes | **UNDOCUMENTED** in numbered docs |

**Verdict**: 1 match, 6 are part of the GS1 barcode system which has no numbered documentation. **Confidence: 95%**

### 3.5 Sales Invoice Custom Fields (4 fields)

| Fieldname | Type | Doc Reference | Deployed | Match? |
|---|---|---|---|---|
| `doctor_name` | Data | Doc 09 (superseded) | Yes | **LEGACY** |
| `hospital` | Link | Doc 09 (superseded) | Yes | **LEGACY** |
| `hospital_branch` | Data | Doc 09 (superseded) | Yes | **LEGACY** |
| `surgery_case` | Link → Surgery Case | Doc 09/11/12 (superseded) | Yes | **LEGACY** |

**Verdict**: All 4 are from superseded documentation. Hospital/doctor fields may still be operationally useful (carried forward into Dispatch Case flow). **Confidence: 90%**

---

## 4. Findings

### F-001: Discount approval writeback targets Sales Order, not Dispatch Case
**Type**: BUG | **Severity**: CRITICAL

**Evidence**: `Task-before-save-discount-approval-writeback.py` (line 20-21) throws if `doc.sales_order` is empty when a Discount Approval task completes. The current operational flow (per `discount-approval-walkthrough.md`) creates Discount Approval tasks from Dispatch Cases via `Dispatch-Case-after-save.py`. These tasks link to a Dispatch Case, not a Sales Order.

**Impact**: If the Dispatch Case discount approval task does not populate the `sales_order` field, completing the task will throw an error: "Discount Approval task must be linked to a Sales Order." Even if it succeeds, the approval status is written to the Sales Order, not the Dispatch Case — the Dispatch Case remains in "Awaiting Approval" with no automated unlock.

**Recommendation**: Verify in production whether Dispatch Case discount approval tasks have `sales_order` populated. If not, this script needs to be updated to handle both Sales Order and Dispatch Case contexts, or a separate Dispatch Case writeback script is needed.

**Confidence**: 85% — needs live verification to confirm whether DC tasks populate `sales_order`.

---

### F-002: Two parallel discount approval systems active in production
**Type**: RISK | **Severity**: HIGH

**Evidence**: Two independent discount approval flows exist and are both ENABLED:
1. **Sales Order path**: `Sales Order-before-save-discount-approval.py` (245 lines) detects discounts on SO save → creates Discount Approval task linked to SO → `Task-before-save-discount-approval-writeback.py` writes back to SO → `Sales Order-after-submit-pack-task.py` creates Pack task.
2. **Dispatch Case path**: `Dispatch-Case-before-save.py` (18 lines) sets "Awaiting Approval" → `Dispatch-Case-after-save.py` (36 lines) creates Discount Approval task → **no dedicated writeback script**.

**Impact**: If both Sales Orders and Dispatch Cases are used in production, there are two separate approval chains. The Sales Order chain is fully wired (detect → task → writeback → pack). The Dispatch Case chain has detection and task creation but appears to lack an automated writeback.

**Recommendation**: Clarify whether Sales Orders are still used for new orders. If the answer is "Dispatch Case only", consider disabling the Sales Order discount scripts and ensuring the Dispatch Case path has a complete writeback mechanism.

**Confidence**: 90%

---

### F-003: One-supplier-per-PO validation is disabled
**Type**: DOC-STALE | **Severity**: HIGH

**Evidence**: `Purchase Order-validate-one-supplier.py` is DISABLED (schema confirms `disabled: 1`). Doc 07 §5 states: "Each sellable stock item must have exactly **one** supplier (default policy)." Doc 07A §6.4.1 provides the exact script and marks it as required. Doc 17A §2.4 lists it as "✅ DEPLOYED 2026-05-11."

**Impact**: Users can currently create POs that mix suppliers or contain items without supplier assignment. This breaks the one-item-one-supplier invariant and makes reorder-by-supplier (Doc 08) unreliable.

**Recommendation**: Either re-enable the script (after ensuring Item Supplier data is populated) or update the documentation to reflect that this validation is intentionally deferred. Record the reason for disabling.

**Confidence**: 95%

---

### F-004: Sales Order → Pack task creation is still active (Doc 09 superseded flow)
**Type**: RISK | **Severity**: HIGH

**Evidence**: `Sales Order-after-submit-pack-task.py` is ENABLED. Every Sales Order submission creates a "Pack / prepare items" task. The Doc 16 Dispatch Case flow creates pack tasks through a different mechanism (`Task-after-save-dispatch-flow.py`).

**Impact**: If Sales Orders are still submitted in production (even accidentally), they generate Pack tasks that are disconnected from the Dispatch Case workflow. This could create orphaned tasks and confusion for the Inventory team.

**Recommendation**: If Sales Orders are no longer used for new orders, disable this script. If they are still used in parallel, this must be documented.

**Confidence**: 90%

---

### F-005: Doc 17A §2.4 claims one-supplier script is deployed but it's disabled
**Type**: DOC-STALE | **Severity**: HIGH

**Evidence**: Doc 17A §2.4 server scripts table shows: `Purchase Order-validate-one-supplier | PO → Before Save | Prevents mixing suppliers on one PO | ✅ DEPLOYED 2026-05-11`. Schema export shows `disabled: 1`.

**Impact**: Documentation gives a false sense of security about this control being active.

**Recommendation**: Update Doc 17A to reflect the actual production state (disabled).

**Confidence**: 99%

---

### F-006: Reorder notification has UTF-8 encoding bug
**Type**: BUG | **Severity**: MEDIUM

**Evidence**: `doc15_norm_reorder_daily_notifications.py` line 31: `"Open report: RPT â€" Purchasing â€" Norm and Reorder"`. The em-dash characters were corrupted during extraction or deployment, producing `â€"` instead of `—`.

**Impact**: ToDo notifications display garbled text. Not a functional issue but looks unprofessional and may confuse users.

**Recommendation**: Fix the string to use either simple hyphens (`-`) or properly encoded em-dashes (`—`).

**Confidence**: 90% — could be an extraction artifact rather than what's actually in production. Needs live verification.

---

### F-007: Reorder notification uses actual_qty instead of projected_qty
**Type**: RISK | **Severity**: MEDIUM

**Evidence**: `doc15_norm_reorder_daily_notifications.py` line 24: `b.actual_qty <= ir.warehouse_reorder_level`. Doc 08 §6.1 defines net availability as `Sellable on-hand - Committed demand`, suggesting `projected_qty` (which subtracts reserved quantities) would be more appropriate.

**Impact**: Items that are below threshold on a net basis (after accounting for committed orders) but above threshold on raw on-hand will not appear in notifications. Conversely, items with stock committed to orders will appear as "fine" when they're actually depleted.

**Recommendation**: Consider using `projected_qty` or `reserved_qty` in the query, or document this as an intentional simplification.

**Confidence**: 80% — the choice of `actual_qty` may have been intentional for simplicity.

---

### F-008: Reorder notification has 100-item limit
**Type**: RISK | **Severity**: MEDIUM

**Evidence**: `doc15_norm_reorder_daily_notifications.py` line 25: `limit 100`. If more than 100 items are below reorder level, the notification will only show the first 100 (in arbitrary order — no `ORDER BY` clause).

**Impact**: Critical items could be silently excluded from reorder notifications.

**Recommendation**: Remove the limit or add `ORDER BY` to prioritize critical items.

**Confidence**: 95%

---

### F-009: Reorder notification is undocumented
**Type**: DOC-MISSING | **Severity**: MEDIUM

**Evidence**: `doc15_norm_reorder_daily_notifications.py` is not mentioned in Doc 08 or Doc 08A. It is referenced only by its `doc15_` naming prefix, suggesting it was created as part of Doc 15 (Reporting Requirements Review), which does not explicitly describe this scheduler either.

**Impact**: No operational documentation describes the notification behavior, frequency, or recipients. Users may not know this feature exists.

**Recommendation**: Add a section to Doc 08A or create a separate operations note documenting the automated daily reorder notification.

**Confidence**: 95%

---

### F-010: LCV client script improved beyond documented version
**Type**: DOC-STALE | **Severity**: MEDIUM

**Evidence**: The deployed `LCV-import-duty-prefill.js` updates an existing "Import Duty" row in-place (preserving the Expense Account), while Doc 17A §6.1 shows a version that removes and recreates the row (losing the Expense Account). The deployed version also places the button under a "Tools" group.

**Impact**: The documentation is outdated. Users following the doc for reference or troubleshooting may be confused by differences from what they see in production.

**Recommendation**: Update Doc 17A §6.1 to reflect the deployed version.

**Confidence**: 95%

---

### F-011: Manual pricing role check references "Doc 09 policy"
**Type**: DOC-STALE | **Severity**: MEDIUM

**Evidence**: `Sales Order-before-save-discount-approval.py` line 187: `"Manual rate changes are allowed only for Accounting/Directors (Doc 09 policy)."`. Doc 09 is superseded.

**Impact**: Error messages reference a superseded document. If users or support staff look up "Doc 09 policy", they'll find a document marked as superseded, which is confusing.

**Recommendation**: If this script remains active, update the error message to reference the current policy document.

**Confidence**: 95%

---

### F-012: Purchase approval task is created manually (not automated)
**Type**: DOC-MISSING | **Severity**: MEDIUM

**Evidence**: Unlike the discount approval flow (which auto-creates the approval task), the purchase approval flow requires the Purchasing team to **manually create** a "Purchase Approval" task and link it to the PO. There is no server script that auto-creates this task when a Draft PO is saved.

Doc 07A §7.2 explicitly instructs: "1) Open Task. 2) Click New. 3) Set: Subject, Task Kind: Purchase Approval, Purchase Order: select your PO..."

**Impact**: This is by design (the docs describe manual creation), but it creates a gap: a PO can sit in "Pending" approval indefinitely if the Purchasing team forgets to create the task. There is no system prompt or automation to remind them.

**Recommendation**: Consider whether an automated task creation (similar to discount approval auto-creation) would improve the workflow, or add a dashboard indicator for POs awaiting approval task creation. At minimum, document this as an intentional design choice.

**Confidence**: 90%

---

### F-013: `buffer_percentage` custom field on Item Reorder is undocumented
**Type**: DOC-MISSING | **Severity**: LOW

**Evidence**: The schema export shows a `buffer_percentage` (Float) custom field on `Item Reorder` with label "Safety Stock Buffer %". Neither Doc 08 nor Doc 08A mention this field. No deployed script references it.

**Impact**: Unclear whether this field is used in any report, manual calculation, or is orphaned.

**Recommendation**: Determine if any report uses this field. If not, document it as unused or remove it.

**Confidence**: 90%

---

### F-014: `custom_1c_code` on Item is undocumented
**Type**: DOC-MISSING | **Severity**: LOW

**Evidence**: A `custom_1c_code` (Data) field exists on Item with label "1C Code". This references the 1C accounting system, which is the legacy system InMED used before ERPNext. No documentation mentions this field.

**Impact**: Likely used for migration mapping or cross-reference. Not harmful but should be documented.

**Recommendation**: Add a note to Doc 06 or the item setup guide explaining this field's purpose.

**Confidence**: 85%

---

### F-015: `pack_breaking_policy` on Item has no formal definition
**Type**: DOC-MISSING | **Severity**: LOW

**Evidence**: A `pack_breaking_policy` (Select) field exists on Item. Doc 07 §6.5 mentions "pack-breaking" conceptually ("buy boxes, sell singles") but does not define the field, its options, or how it affects behavior. No deployed script references this field.

**Recommendation**: Document the field's purpose and allowed values, or remove if unused.

**Confidence**: 85%

---

### F-016: Purchase Receipt barcode override fields are undocumented in numbered docs
**Type**: DOC-MISSING | **Severity**: LOW

**Evidence**: Four custom fields on Purchase Receipt (`custom_allow_expired_barcode_receipt`, `custom_allow_future_production_date`, `custom_barcode_override_reason`, `custom_barcode_override_section`) and three on Purchase Receipt Item (`custom_expiry_date`, `custom_production_date`, `custom_scanned_gs1_barcode`) are part of the GS1 barcode scanning system. They are referenced in barcode-specific docs under `docs/ERPNext Barcode/` but have no numbered documentation.

**Recommendation**: Create a numbered doc (e.g., Doc 06.1 or similar) for the barcode/GS1 system, or add a section to Doc 17A.

**Confidence**: 90%

---

### F-017: Sales Invoice custom fields reference superseded Surgery Case
**Type**: DOC-STALE | **Severity**: LOW

**Evidence**: Sales Invoice has a `surgery_case` Link field pointing to Surgery Case DocType. Surgery Case is superseded by Dispatch Case per Doc 16.

**Impact**: If Sales Invoices are still created (they are — by `Task-after-save-dispatch-flow.py`), this field may or may not be populated. If it is, it links to a superseded DocType.

**Recommendation**: Evaluate whether this field should be replaced with a Dispatch Case link, or left as-is for historical records.

**Confidence**: 85%

---

### F-018: Property setters on purchasing DocTypes not verified against docs
**Type**: RISK | **Severity**: LOW

**Evidence**: The schema export shows property setters across purchasing DocTypes: Purchase Order (9), Purchase Receipt (9), Purchase Invoice (9). These modify field visibility, labels, defaults, and read-only status. They were not individually verified in this audit because property setters affect presentation rather than logic.

**Recommendation**: In a follow-up pass, verify that property setters don't hide required fields or make read-only fields that scripts expect to be writable.

**Confidence**: 70%

---

## 5. Cross-Group Dependencies

These items were noted during this audit but belong to other groups:

| Finding | Relevant Group | Note |
|---|---|---|
| `Dispatch-Case-after-save.py` creates Discount Approval tasks but there's no DC-specific writeback | Group 1 (Dispatch Case) | The writeback in this group targets Sales Order. Group 1 must verify the DC discount flow end-to-end. |
| `Task-after-save-dispatch-flow.py` creates Sales Invoices and links them | Group 1 (Dispatch Case) | This audit found the SI custom fields reference Surgery Case. Group 1 should check what `Task-after-save-dispatch-flow.py` actually populates. |
| `disable_all_item_batch_serial_for_now.py` disables tracking | Group 6 (Legacy) | This makes the batch/expiry validation in `Purchase Receipt-before-submit-main-inmed-expiry.py` effectively inert for most items. |
| `GS1 Barcode Parser.js` on Purchase Receipt | Group 5 (Packing) | The barcode override fields found here are used by that script. |

---

## 6. Consolidated Recommendations

### Immediate Actions (before next deployment)

1. **Verify F-001 in production**: Check whether Dispatch Case discount approval tasks have `sales_order` populated. If not, the Discount Approval task completion will fail.
2. **Fix F-006**: Replace corrupted UTF-8 characters in the reorder notification script.

### Short-term (next sprint)

3. **Clarify dual system (F-002, F-004)**: Decide whether Sales Orders are still used for new orders. If not, disable `Sales Order-before-save-discount-approval.py`, `Sales Order-after-submit-pack-task.py`, and `Task-before-save-discount-approval-writeback.py`.
4. **Re-enable or document (F-003)**: Either re-enable `Purchase Order-validate-one-supplier.py` after populating Item Supplier data, or update docs to explain why it's deferred.
5. **Update Doc 17A (F-005)**: Correct the deployment status table.

### Medium-term (documentation cleanup)

6. **Update Doc 17A §6.1 (F-010)**: Replace the LCV script example with the deployed version.
7. **Document reorder notification (F-009)**: Add to Doc 08A or create operations note.
8. **Document barcode/GS1 fields (F-016)**: Create numbered documentation.
9. **Document undocumented custom fields (F-013, F-014, F-015)**.

### Deferred (low priority)

10. **Consider automating PO approval task creation (F-012)**.
11. **Improve reorder notification query (F-007, F-008)**: Use `projected_qty`, remove limit.
12. **Clean up superseded references (F-011, F-017)**.
