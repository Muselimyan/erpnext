# Go-Live Status Report
**Generated:** 2026-05-18 11:39  
**Last Updated:** 2026-05-19 15:37

---

## ✅ What's Already Working (No Action Needed)

### Manual Go-Live Setup
- ✅ **BLOCKER #1: Role Permission Manager** completed manually in ERPNext UI
- ⚠️ **API verification limitation:** current API checks could not reliably read Role Permission Manager internals (`403` / `417` responses), but user confirmed the permissions are visible and persisted after refresh/reopen in ERPNext UI
- ✅ **BLOCKER #2: Item Tracking Flags** completed, applied, and post-apply verified from V3 item-level review

### Deployment Scripts
- ✅ **All 13 deployment scripts verified** (doc07a through doc17a)
- ✅ **2 missing components deployed today:**
  - `Collection-Set-validate-readiness` server script (doc11a)
  - 4 missing reports (doc13a): Delivery In-Transit, Return Pickup In-Transit, Returns, Surgery Cases Aging

### Master Data
- ✅ **193 customers** loaded with debt thresholds set (not 0)
- ✅ **Item tracking review covered 3318 source rows**
- ✅ **ERPNext item tracking verification matched 3318 reviewed rows** (`Already OK: 3318`, `Would update: 0`)
- ✅ **Test customer `TEST01`** already deleted
- ✅ **Standard Selling price list:** 1,000 prices populated

### Users & Roles
- ✅ **8/9 example users** exist and enabled:
  - `accounting.team@example.com`
  - `dispatch.coordinator@example.com`
  - `driver.01@example.com`
  - `finance.team@example.com`
  - `inventory.team@example.com`
  - `order.creation.team@example.com`
  - `order.team@example.com`
  - `returns.team@example.com`
- ✅ **16 Task Access Policy** records exist

### System Health
- ✅ **No draft Purchase Orders** with missing required fields
- ✅ **No malformed Tasks** (all have correct assignee count)
- ✅ **Server scripts** deployed and enabled

### Barcode / Purchase Receipt Draft Logic
- ✅ **Row merge rule checked locally:** current GS1 draft logic merges only when `Item + LOT + Expiry Date` all match
- ✅ **Different expiry dates stay separate:** same REF + same LOT + different expiry should not merge in the draft scanning logic

---

## ⚠️ What Still Needs Attention

### ✅ **DONE: BLOCKER #1: Role Permission Manager**
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
| **Workspace: Ops — Reporting Pack** | `Ops - Order Accepting`, `Ops - Inventory`, `Accounting`, `Director` | Read / accessible |

**Keep this table for troubleshooting if any user later gets Permission Denied.**

---

### ✅ **DONE: BLOCKER #2: Item Tracking Flags**
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

### 🟡 **WARNING: Standard Buying Price List Empty** (Variable time)
**Why:** Profit reports will show 0 until buying prices are populated  
**Impact:** Medium - reports won't show margins, but sales can proceed  
**Current state:** 0 buying prices vs 1,000 selling prices

**Options:**
1. **If you have buying price data:** Provide CSV, I can bulk-import
2. **If you need to enter manually:** Use ERPNext Item Price list
3. **If you want to defer:** Can go live without this; profit reports just won't work yet

---

### 🟢 **OPTIONAL: Saved Views** (10-15 minutes)
**Why:** Per-user saved views cannot be created via API  
**Impact:** Low - improves usability but not blocking  

**Views to create (if desired):**
- `Stock Balance — Main - Inmed` (Stock Balance report, filter: Warehouse = Main - Inmed)
- `Items — Active Stock` (Item list, filter: Disabled = No, Is Stock Item = Yes)
- `Reorder — Main - Inmed` (Stock Reorder tool, filter: Warehouse = Main - Inmed)
- `Price Overrides — by Client` (Item Price list, filter: Price List = Standard Selling, Customer ≠ blank)
- Dispatch Case state views (per status)
- Task queue views (per task_kind)

**How:** Open each DocType/Report, apply filters, click "Save" → give it a name

---

### 🟢 **OPTIONAL: Missing Example User** (30 seconds)
**Why:** `director.01@example.com` not found (might be renamed or deleted)  
**Impact:** None if you're using real users  
**Action:** Verify if this user exists under a different name, or ignore if using real directors

---

## 📋 Next Steps (Recommended Order)

1. **Done:** Item tracking review and ERPNext Item flag update
2. **Next:** Verify/deploy Purchase Receipt barcode scanning if not already live
3. **Next:** Assign real users to operational roles
4. **Next:** Run end-to-end smoke tests
5. **You decide (MEDIUM):** Standard Buying prices - defer or populate?

---

## 🚀 After These Are Done, You're Ready For:

1. **End-to-end smoke tests** (go-live-action-plan.md Section 7)
2. **First real transaction**
3. **Team training on the new workflows**

---

## Files Created Today

- `deploy/check_system_status.ps1` - Automated status checker (re-run anytime)
- `deploy/system-status-report.json` - Latest status snapshot
- `deploy/create_missing_task_policies.ps1` - Task Access Policy creator (already run)
- `GO-LIVE-STATUS.md` - This file

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
