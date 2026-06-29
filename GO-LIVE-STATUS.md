# Go-Live Status Report
**Generated:** 2026-05-18 11:39  
**Last Updated:** 2026-06-12 11:37

## Current Launch Decision — 2026-06-01 16:35

- **Smoke tests / role access checks:** deferred to the first testing month after launch. This is accepted because the owner is currently testing alone and workers will help discover real workflow problems during live use.
- **Standard Buying prices:** deferred for now. Sales/dispatch can proceed; profit and margin reports may show incomplete or zero margins until buying prices are populated.
- **Import tax rates:** not needed for launch and deferred indefinitely. The Doc 17A import-duty automation exists but does not need to be used immediately.
- **Reorder levels / reorder quantities:** deferred to the testing month. Low-stock/reorder reports may be incomplete until these are populated.
- **HS codes:** recommended but not launch-blocking. Add them later for customs/import clarity and cleaner purchasing records.
- **Safe AI checks:** AI can run read-only/API readiness checks and fix obvious technical errors, but should not create real operational smoke-test transactions unless explicitly approved.

---

## âœ… What's Already Working (No Action Needed)

### Manual Go-Live Setup
- âœ… **BLOCKER #1: Role Permission Manager** completed manually in ERPNext UI
- âš ï¸ **API verification limitation:** current API checks could not reliably read Role Permission Manager internals (`403` / `417` responses), but user confirmed the permissions are visible and persisted after refresh/reopen in ERPNext UI
- âœ… **BLOCKER #2: Item Tracking Flags** completed, applied, and post-apply verified from V3 item-level review

### Deployment Scripts
- âœ… **All 13 deployment scripts verified** (doc07a through doc17a)
- âœ… **2 missing components deployed today:**
  - `Collection-Set-validate-readiness` server script (doc11a)
  - 4 missing reports (doc13a): Delivery In-Transit, Return Pickup In-Transit, Returns, Surgery Cases Aging

### Master Data
- âœ… **193 customers** loaded with debt thresholds set (not 0)
- âœ… **Item tracking review covered 3318 source rows**
- âœ… **ERPNext item tracking verification matched 3318 reviewed rows** (`Already OK: 3318`, `Would update: 0`)
- âœ… **Test customer `TEST01`** already deleted
- âœ… **Standard Selling price list:** 1,000 prices populated

### Users & Roles
- âœ… **8/9 example users** exist and enabled:
  - `accounting.team@example.com`
  - `dispatch.coordinator@example.com`
  - `driver.01@example.com`
  - `finance.team@example.com`
  - `inventory.team@example.com`
  - `order.creation.team@example.com`
  - `order.team@example.com`
  - `returns.team@example.com`
- âœ… **16 Task Access Policy** records exist

### System Health
- âœ… **No draft Purchase Orders** with missing required fields
- âœ… **No malformed Tasks** (all have correct assignee count)
- âœ… **Server scripts** deployed and enabled

### Docs 15/16/17 Launch Readiness
- âœ… **Doc 15A reporting pack complete:** Doc 15A now has 26/26 reports/functions/workspaces deployed or existing
- âœ… **Doc 15E deployed:** reports `RPT â€” Item â€” Sort and Classify`, `RPT â€” Item â€” Nomenclature and Prices`, `RPT â€” Returns â€” Refund Queue`; scheduler `doc15_norm_reorder_daily_notifications`; workspaces `Management â€” KPI Dashboard`, `Dispatch â€” Task Queues`
- âœ… **Doc 16 Dispatch Case core complete:** `Dispatch Case Item.unit_price` is optional in live ERPNext and documentation
- âœ… **Doc 16 workspace polish complete:** `Dispatch â€” Task Queues` provides the operational Dispatch/Task shortcuts
- âœ… **Doc 17A technical components deployed:** item HS/import-tax fields and LCV import-duty pre-fill are deployed

### Barcode / Purchase Receipt Draft Logic
- âœ… **Row merge rule checked locally:** current GS1 draft logic merges only when `Item + LOT + Expiry Date` all match
- âœ… **Different expiry dates stay separate:** same REF + same LOT + different expiry should not merge in the draft scanning logic

---

## âš ï¸ What Still Needs Attention

### âœ… **DONE: BLOCKER #1: Role Permission Manager**
**Status:** Completed manually in ERPNext UI  
**Verification:** User confirmed rows are visible after refresh/close/open  
**API note:** REST/API diagnostics could not fully verify permission-manager internals because ERPNext returned `403 Forbidden` / `417 Expectation Failed` for permission internals. If role access fails during smoke tests, revisit this section.

**Required permissions per DocType:**

| DocType | Role | Permissions Needed |
|---------|------|-------------------|
| **Dispatch Case** | `Ops - Order Creating` | Read, Write, Create, Submit |
| | `Ops - Order Accepting` | Read |
| | `Ops - Accounting`, `Ops - Inventory`, `Ops - Returns`, `Delivery Driver` | Read |
| | `Ops - Directors` | Read, Cancel |
| **Stock Entry** | `Ops - Inventory`, `Ops - Delivery`, `Ops - Returns` | Read, Write, Create, Submit |
| | `Delivery Driver` | No access |
| **Sales Invoice** | `Ops - Accounting` | Read, Write, Create, Submit, Cancel |
| | `Ops - Finance` | Read |
| **Payment Entry** | `Ops - Accounting` | Read, Write, Create, Submit, Cancel |
| | `Ops - Finance` | Read, Write, Create, Submit, Cancel |
| **Task** | `Ops - Finance` | Read, Write (own tasks only - enforced by script) |
| **Item**, **Item Group**, **Item Attribute**, **UOM** | `Ops - Inventory`, `Ops - Directors` | Write, Create |
| | All other roles | Read only |
| **Workspace: Ops â€” Reporting Pack** | `Ops - Order Accepting`, `Ops - Inventory`, `Accounting`, `Director` | Read / accessible |

**Keep this table for troubleshooting if any user later gets Permission Denied.**

---

### âœ… **DONE: BLOCKER #2: Item Tracking Flags**
**Why it mattered:** Must be set BEFORE first stock transaction; wrong flags create permanent data quality problems.  
**Status:** Completed using item-level V3 classification and applied to ERPNext.

**Final review files:**
- `deploy/item-tracking-review-v3.csv`
- `deploy/item-tracking-group-summary-v3.csv`
- `deploy/item-tracking-update-dry-run.csv`
- `deploy/update_item_tracking_flags.py`

**Final classification:**
- `BATCH_EXPIRY`: 743 items
- `REF_ONLY`: 2575 items
- `MANUAL_REVIEW`: 0
- `HIGH risk`: 0

**Final post-apply verification:**
- `Already OK`: 3318
- `Would update`: 0
- `Missing`: 0
- `Ambiguous`: 0
- `Errors`: 0

**Applied tracking meaning:**
- `BATCH_EXPIRY` = `has_batch_no = 1`, `has_expiry_date = 1`, `has_serial_no = 0`
- `REF_ONLY` = `has_batch_no = 0`, `has_expiry_date = 0`, `has_serial_no = 0`
- No serial tracking enabled for go-live.

**Detailed handover:** see `GO-LIVE-HANDOVER-SUMMARY.md`.

---

### ðŸŸ¡ **WARNING: Standard Buying Price List Empty** (Variable time)
**Why:** Profit reports will show 0 until buying prices are populated  
**Impact:** Medium - reports won't show margins, but sales can proceed  
**Current state:** 0 buying prices vs 1,000 selling prices

**Options:**
1. **If you have buying price data:** Provide CSV, I can bulk-import
2. **If you need to enter manually:** Use ERPNext Item Price list
3. **If you want to defer:** Can go live without this; profit reports just won't work yet

---

### ðŸŸ¢ **OPTIONAL: Saved Views** (10-15 minutes)
**Why:** Per-user saved views cannot be created via API  
**Impact:** Low - improves usability but not blocking. Doc 15E added clean workspaces, so this is less urgent than before.  

**Views to create (if desired):**
- `Stock Balance â€” Main - Inmed` (Stock Balance report, filter: Warehouse = Main - Inmed)
- `Items â€” Active Stock` (Item list, filter: Disabled = No, Is Stock Item = Yes)
- `Reorder â€” Main - Inmed` (Stock Reorder tool, filter: Warehouse = Main - Inmed)
- `Price Overrides â€” by Client` (Item Price list, filter: Price List = Standard Selling, Customer â‰  blank)
- Dispatch Case state views (per status)
- Task queue views (per task_kind)

**How:** Open each DocType/Report, apply filters, click "Save" â†’ give it a name

---

### ðŸŸ¢ **OPTIONAL: Missing Example User** (30 seconds)
**Why:** `director.01@example.com` not found (might be renamed or deleted)  
**Impact:** None if you're using real users  
**Action:** Verify if this user exists under a different name, or ignore if using real directors

---

## ðŸ§ª Smoke Test Progress

### Surgery Case Walkthrough (`docs/manual/surgery-case-walkthrough-v2.md`)
**Last tested:** 2026-06-12  
**Note:** Using v2 walkthrough which reflects barcode scanning automation. Original walkthrough kept as reference.

| Step | Status | Notes |
|------|--------|-------|
| **Step 1: Create Order entry task** | âœ… **Fully functioning** | Task creation, product lines, assignment working correctly |
| **Step 2: Create and submit Dispatch Case** | âœ… **Fully functioning** | Case creation from task, item copy, return_expected flag, submit workflow all working |
| Step 2a: Discount approval | ⏳ Pending test | Only needed if discount > 0 |
| Step 3: Pack task (barcode scanning) | ⏳ Pending test | Accept/Start task, Product Work Area scanning, FEFO warnings, auto-fill batch/serial |
| Step 4: Delivery - Picked Up | ⏳ Pending test | |
| Step 5: Delivery - Delivered | ⏳ Pending test | |
| Step 6: Return Waiting | ⏳ Pending test | |
| Step 7: Return Pickup - Picked Up | ⏳ Pending test | |
| Step 8: Return Pickup - Returned | ⏳ Pending test | |
| Step 9: Returns Inspection | ⏳ Pending test | |
| Step 10: Restock task | ⏳ Pending test | |
| Step 11: Invoice Preparation | ⏳ Pending test | |
| Step 12: Debt Collection | ⏳ Pending test | |

**Next smoke test step:** Step 3 (Pack task completion)

---

## ðŸ“‹ Next Steps (Recommended Order)

1. **Done:** Item tracking review and ERPNext Item flag update
2. **Done:** Doc 15E remaining reports/scheduler/workspaces deployed
3. **Done:** Doc 16 `unit_price` made optional and Dispatch task workspace deployed
4. **In Progress:** End-to-end smoke tests (Surgery Case Walkthrough: Steps 1-2 âœ…, Step 3+ pending)
5. **You decide (MEDIUM):** Standard Buying prices - defer or populate?
6. **You decide (MEDIUM):** Populate HS codes and import tax rates for purchase costing reports/LCV automation

---

## ðŸš€ After These Are Done, You're Ready For:

1. **End-to-end smoke tests** (`docs/go-live-action-plan.md` Section 7)
2. **First real transaction**
3. **Team training on the new workflows**

---

## Files Created Today

- `deploy/check_system_status.ps1` - Automated status checker (re-run anytime)
- `deploy/system-status-report.json` - Latest status snapshot
- `deploy/create_missing_task_policies.ps1` - Task Access Policy creator (already run)
- `GO-LIVE-STATUS.md` - This file
- `deploy/doc15e-deploy.ps1` - Doc 15E final reporting/workspace deployment script

---

## Questions?

**Q: Can I use real users instead of example users?**  
A: Yes! The example users are just placeholders. Assign real staff to the operational roles, then disable/delete the example users after go-live.

**Q: What if I make a mistake in Role Permission Manager?**  
A: You can always go back and edit. Worst case: users get "Permission Denied" errors, you add the missing permission.

**Q: What happens if I set wrong tracking flags?**  
A: **This is the only irreversible one.** Once a stock transaction exists for an item, ERPNext locks the tracking flags. Choose carefully or test with a few items first.

**Q: Can I skip Standard Buying prices?**  
A: Yes, for now. Sales will work fine. Only profit reports will show 0 margin until you populate buying prices later.
