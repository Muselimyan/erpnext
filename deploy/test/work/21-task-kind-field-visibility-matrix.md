# 21 — Task Kind Field Visibility Matrix

**Date:** 2026-09-01
**Method:** Cross-referenced `custom-fields.json` (52 Task fields), `property-setters.json` (40 Task setters), 11 client scripts, and 5 server scripts from `deploy/test/schema/` and `deploy/test/work/`.
**No assumptions.** Every cell traced to a `depends_on` expression, property setter, or client script line.

---

## Table of Contents

1. [Task Kind Groups](#1-task-kind-groups)
2. [Core Field Visibility Matrix](#2-core-field-visibility-matrix)
3. [Specialized Field Visibility Matrix](#3-specialized-field-visibility-matrix)
4. [Action Buttons per Task Kind](#4-action-buttons-per-task-kind)
5. [Client Script Overrides Detail](#5-client-script-overrides-detail)
6. [Mobile-Specific Differences](#6-mobile-specific-differences)
7. [Server-Side Completion Gates](#7-server-side-completion-gates)
8. [Discrepancies and Inconsistencies](#8-discrepancies-and-inconsistencies)
9. [Field Reference](#9-field-reference)

---

## 1. Task Kind Groups

24 task kinds exist in the `task_kind` Select field. Grouped by functional similarity:

| Group | Task Kinds | Count |
|---|---|---|
| **A. Dispatch flow** | Order entry, Pack / prepare items, Dispatch picking / hand-off, Delivery, Pickup Returns, Return drop-off at warehouse, Returns processing / verification, Returns restocking, Invoice preparation / create invoice, Discount Approval | 10 |
| **B. Returns initiation** | Return Call | 1 |
| **C. Debt / payment** | Debt Collection, Distribute Payment, Payment Received, Debt Closure Approval | 4 |
| **D. Approvals** | Purchase Approval, Write-off Approval | 2 |
| **E. Account details** | Account Details: Entry, Account Details: Processing | 2 |
| **F. Other** | Other, Other: Entry, Other: Processing | 3 |
| **G. Legacy / unused** | Order accepting, Return to warehouse (aborted delivery / cancelled order) | 2 |

**Notes on Group G:**
- `Order accepting` is immediately replaced with `Order entry` on new task creation (client script `Task-Accept Start.js` line 161). No code path handles it as a distinct kind.
- `Return to warehouse (aborted delivery / cancelled order)` is not referenced in any client or server script.

---

## 2. Core Field Visibility Matrix

Fields that should arguably appear on most/all task kinds. These are the ones where discrepancies matter most.

Legend: **V** = Visible, **H** = Hidden, **M-H** = Hidden on mobile only, **CS** = Client script override, **PS** = Property setter, **CF** = Custom field depends_on, **--** = N/A

| Field | Order entry | Pack | Dispatch pick | Delivery | Return Call | Pickup Ret. | Ret. drop-off | Returns proc. | Ret. restock | Invoice prep | Discount Appr. |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **subject** | H (CS) | M-H (CS) | V | V | V | V | V | V | V | V | V |
| **task_kind** | V | M-H (CS) | V | V | V | V | V | V | V | V | V |
| **completed_at** | V | M-H (CS) | V | V | V | V | V | V | V | V | V |
| **customer** | V | M-H (CS) | V | V | V | V | V | V | V | V | V |
| **custom_assigned_to** | V | M-H (CS) | V | V | V | V | V | V | V | V | V |
| **custom_accepted_by** | H (CS) | H (CS) | H (CS) | H (CS) | H (CS) | H (CS) | H (CS) | H (CS) | H (CS) | H (CS) | H (CS) |
| **custom_accepted_at** | M-H (CS) | M-H (CS) | M-H (CS) | M-H (CS) | M-H (CS) | M-H (CS) | M-H (CS) | M-H (CS) | M-H (CS) | M-H (CS) | M-H (CS) |
| **custom_next_task_assign_to** | V (CS) | V (CS) | H (CF) | V (CS) | V (CF) | H (CF) | H (CF) | V (CS) | H (CF) | H (CF) | V (CS) |
| **status** | V | V | V | V | V | V | V | V | V | V | V |
| **priority** | V | V | V | V | V | V | V | V | V | V | V |
| **description** | V | V | V | V | V | V | V | V | V | V | V |

| Field | Debt Collect. | Distrib. Pay. | Payment Rec. | Debt Clos. Appr. | Purchase Appr. | Write-off Appr. | Acct Det. Entry | Acct Det. Proc. | Other | Other: Entry | Other: Proc. |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **subject** | V | V | V | V | V | V | V (CS) | V (CS) | V (CS) | V (CS) | V (CS) |
| **task_kind** | V | V | V | V | V | V | V | V | V | V | V |
| **completed_at** | V | V | V | V | V | V | V | V | V | V | V |
| **customer** | V | V | V | V | V | V | V | V | V | V | V |
| **custom_assigned_to** | V | V | V | V | V | V | V | V | V | V | V |
| **custom_accepted_by** | H (CS) | H (CS) | H (CS) | H (CS) | H (CS) | H (CS) | H (CS) | H (CS) | H (CS) | H (CS) | H (CS) |
| **custom_accepted_at** | M-H (CS) | M-H (CS) | M-H (CS) | M-H (CS) | M-H (CS) | M-H (CS) | M-H (CS) | M-H (CS) | M-H (CS) | M-H (CS) | M-H (CS) |
| **custom_next_task_assign_to** | H (CF) | H (CF) | H (CF) | H (CF) | H (CF) | H (CF) | V (CS) | H (CF) | H (CF) | V (CF) | V (CF) |
| **status** | V | V | V | V | V | V | V (CS) | V (CS) | V (CS) | V (CS) | V (CS) |
| **priority** | V | V | V | V | V | V | V (CS) | V (CS) | V (CS) | V (CS) | V (CS) |
| **description** | V | V | V | V | V | V | V | V | V | V | V |

### Source notes for core fields

| Field | Visibility source |
|---|---|
| subject | **Always visible** by default (PS: reqd=0). **Order entry**: hidden by `Task-Accept Start.js:140`. **Pack mobile**: hidden by `Task-Mobile Form Layout Fix.js:266-279`. `Task-Header Long Subject Fix.js` forces it visible on every refresh — but runs before Mobile Layout Fix which re-hides it for Pack. **Account Details + Other**: shown explicitly by their cleanup scripts. |
| task_kind | **Always visible** by default. **Pack mobile**: hidden by `Task-Mobile Form Layout Fix.js:253-255` (class `task-mobile-pack-hidden`). |
| completed_at | **Always visible** (no depends_on, no client override). **Pack mobile**: hidden by `Task-Mobile Form Layout Fix.js:253`. |
| customer | **Always visible** (no depends_on). **Pack mobile**: hidden when value is empty by `Task-Mobile Form Layout Fix.js:260`. |
| custom_assigned_to | **Always visible** (no depends_on). **Pack mobile**: hidden by `Task-Mobile Form Layout Fix.js:253`. |
| custom_accepted_by | **Always** hidden by `Task-Accept Start.js:134`. Internal field. |
| custom_accepted_at | **Always** hidden on mobile by `Task-Accept Start.js:151`. Visible on desktop. |
| custom_next_task_assign_to | **Custom field depends_on**: `["Order entry","Pack / prepare items","Delivery","Return Call","Other: Entry","Other: Processing","Returns processing / verification"].includes(doc.task_kind)`. **Client script overrides**: `Task-Accept Start.js` shows it for dispatch kinds + Account Details: Entry. `Task-Delivery UI Fix.js` shows for Delivery. `Task-Inspect Returns Next Assign Visible.js` shows for Returns processing. `Task-Other UI Cleanup.js` shows for Other kinds (conditionally). Net: visible for Order entry, Pack, Delivery, Return Call, Other: Entry, Other: Processing, Returns proc., Account Details: Entry, Discount Approval (via dispatch list). |

---

## 3. Specialized Field Visibility Matrix

Fields that are correctly specialized per task kind. Listed by field group.

### 3.1 Dispatch Case Fields

Controlled by custom field `depends_on` and mirrored by property setter. Visible for the same 9 dispatch kinds.

| Field | Pack | Disp. pick | Delivery | Pickup Ret. | Ret. drop | Ret. proc. | Ret. restock | Invoice prep | Disc. Appr. | All others |
|---|---|---|---|---|---|---|---|---|---|---|
| dispatch_case | V | V | V | V | V | V | V | V | V | H |
| dispatch_case_status | V | V | V | V | V | V | V | V | V | H |

**Note:** Order entry is NOT in the dispatch_case depends_on list, but it creates DCs and the Action Buttons script will show Create DC / Open DC buttons for it.

### 3.2 Delivery / Returns Status Fields

| Field | Delivery | Pickup Returns | Ret. drop-off | All others |
|---|---|---|---|---|
| delivery_status | V | H | H | H |
| pickup_status | H | V | H | H |
| return_pickup_driver | H | V | V | H |
| scheduled_return_date | H | V | V | H |

### 3.3 Approval Fields

| Field | Purchase Appr. | Discount Appr. | Write-off Appr. | Debt Clos. Appr. | All others |
|---|---|---|---|---|---|
| purchase_order | V | H | H | H | H |
| approval_outcome | V | V | V | H | H |
| approval_note | V | V | V | H | H |

**Note:** Debt Closure Approval does NOT show approval_outcome/approval_note, but the server gate checks a whitelist of allowed users for completion. This is a potential discrepancy — Debt Closure Approval is not in the approval_outcome depends_on.

### 3.4 Invoice / Sales Fields

| Field | Invoice prep | Debt Collect. | Payment Rec. | Distrib. Pay. | Ret. proc. | All others |
|---|---|---|---|---|---|---|
| sales_invoice | V | V | V | V | V | H |
| payment_entry | H | V | V | V | H | H |

### 3.5 Debt / Payment Fields

| Field | Debt Collect. | Distrib. Pay. | Payment Rec. | Debt Clos. Appr. | All others |
|---|---|---|---|---|---|
| current_debt_amd | V | H | H | H | H |
| debt_threshold_amd | V | H | H | H | H |
| new_payment_amount | V | H | V | H | H |
| payment_method_dc | V | H | V | H | H |
| payment_reference_dc | V | H | V | H | H |
| total_outstanding | V | V | H | H | H |
| available_advance_credit | V | V | H | H | H |
| open_invoices | V | V | H | H | H |
| payment_history | V | V | H | H | H |
| custom_case_profit | H | H | H | V | H |
| custom_total_amount_paid | H | H | H | V | H |

### 3.6 Product / Scanning Fields

| Field | Order entry | Pack | Disp. pick | Delivery | Pickup Ret. | All other dispatch | Debt Collect. | Acct Det. | Other kinds | All others |
|---|---|---|---|---|---|---|---|---|---|---|
| custom_product_work_section | V | V | V | V | V | V | V | H (CS) | H (CS) | V |
| custom_task_product_summary | V | V | V | V | V | V | V | H (CS) | H (CS) | V |
| custom_product_lines | H (CF) | V | V | V | V | V | V | H (CS) | H (CS) | V |
| custom_barcode_section | V | V | V | V | V | V | V | H (CS) | V (CS) | V |
| custom_task_scan_barcode | V | V | V | V | V | V | H (CF) | H (CS) | H (CS) | V |
| custom_task_scan_qty | V | V | V | V | V | V | H (CF) | H (CS) | H (CS) | V |
| custom_task_scan_result | V | V | V | V | V | V | H (CF) | H (CS) | H (CS) | V |
| custom_task_add_item_code | V | V | V | V | V | V | V | H (CS) | H (CS) | V |
| custom_task_add_qty | V | V | V | V | V | V | V | H (CS) | H (CS) | V |
| custom_task_add_batch_no | V | V | V | V | V | V | V | H (CS) | H (CS) | V |
| custom_task_add_unit_price | V | V | V | V | V | V | V | H (CS) | H (CS) | V |

**Key discrepancy:** The product/scanning section is visible by default on ALL task kinds (no depends_on on the section or most fields). Only Account Details and Other kinds have client scripts that hide them. Task kinds like Purchase Approval, Write-off Approval, Debt Closure Approval, Distribute Payment, Payment Received still show the entire product scanning section even though it's irrelevant.

### 3.7 Other-Specific Fields

| Field | Other | Other: Entry | Other: Processing | All others |
|---|---|---|---|---|
| other_items | V | H (CS) | H (CS) | H |
| other_budget | V | H (CS) | H (CS) | H |
| other_supplier | V | H (CS) | H (CS) | H |

**Discrepancy:** `other_items`, `other_budget`, `other_supplier` have `depends_on: doc.task_kind=='Other'` — they only show for the legacy `Other` kind. The `Other: Entry` and `Other: Processing` cleanup script ALSO hides them explicitly. So `Other` gets these fields, but `Other: Entry` and `Other: Processing` do not.

### 3.8 Account Details Fields

| Field | Acct Det. Entry | Acct Det. Processing | All others |
|---|---|---|---|
| custom_account_photos | V (CS) | V (CS) | H (CF) |
| custom_account_details_section | H (always) | H (always) | H (always) |
| custom_account_details_entry_task | H (always) | H (always) | H (always) |
| custom_account_details_subject | V | V | V |

**Discrepancy:** `custom_account_photos` has `depends_on: doc.task_kind === "Account details"` (lowercase, no colon). This never matches any real task_kind. It only appears because client scripts (`Task-Accept Start.js:37`, `Task-Account Details UI Cleanup.js:50`) force it visible for Account Details: Entry/Processing.

**Discrepancy:** `custom_account_details_subject` has NO depends_on — it is visible on ALL task kinds. It should probably be restricted to Account Details kinds.

### 3.9 Miscellaneous Fields

| Field | All task kinds | Order entry | Notes |
|---|---|---|---|
| driver_handover_note | H (hidden=1) | H | hidden=1 in custom field definition + depends_on excludes Order entry. Effectively always hidden. |
| dispatch_group_id | H (hidden=1) | H | Internal field, always hidden. |
| task_access_policy | H (hidden=1) | H | Internal field, always hidden. |

### 3.10 Standard Frappe Fields (hidden by property setters)

These standard Task fields are permanently hidden via property setters:

| Field | Status | Source |
|---|---|---|
| project | Hidden | PS hidden=1 |
| issue | Hidden | PS hidden=1 |
| type | Hidden | PS hidden=1 |
| color | Hidden | PS hidden=1 |
| is_group | Hidden | PS hidden=1 |
| task_weight | Hidden | PS hidden=1 |
| parent_task | Hidden | PS hidden=1 |
| is_template | Hidden | PS hidden=1 |

---

## 4. Action Buttons per Task Kind

| Task Kind | Accept | Complete | Create DC | Open DC | Products dropdown | DC info banner |
|---|---|---|---|---|---|---|
| Order entry | V | V | V (if no DC) | V (if DC) | H | V |
| Pack / prepare items | V | V | H | V | V | V |
| Dispatch picking / hand-off | V | V | H | V | V | V |
| Delivery | V | V | H | V | V | V |
| Return Call | V | V | H | H | H | H |
| Pickup Returns | V | V | H | V | V | V |
| Return drop-off at warehouse | V | V | H | V | V | V |
| Returns processing / verification | V | V | H | V | V | V |
| Returns restocking | V | V | H | V | V | V |
| Invoice preparation / create invoice | V | V | H | V | V | V |
| Discount Approval | V | V | H | V | V | V |
| Debt Collection | V | V | H | V | V | V |
| Debt Closure Approval | V | V | H | H | H | H |
| Distribute Payment | V | V | H | H | H | H |
| Payment Received | V | V | H | H | H | H |
| Purchase Approval | V | V | H | H | H | H |
| Write-off Approval | V | V | H | H | H | H |
| Account Details: Entry | V | V | H | H | H | H |
| Account Details: Processing | V | V | H | H | H | H |
| Other | V | V | H | H | H | H |
| Other: Entry | V | V | H | H | H | H |
| Other: Processing | V | V | H | H | H | H |
| Order accepting | V | V | H | H | H | H |
| Return to warehouse | V | V | H | H | H | H |

**Notes:**
- Accept button requires status Open/Working and not accepted by current user.
- Complete button requires accepted by current user (or admin) and not Completed/Cancelled.
- Create DC shown for Order entry + all TAB_DISPATCH_KINDS when no DC linked.
- Products dropdown shown for TAB_PRODUCT_KINDS when accepted. Mobile sub-header only.
- Debt Collection IS in TAB_DISPATCH_KINDS (gets DC banner/button) but NOT in TAB_PRODUCT_KINDS (no Products dropdown).

---

## 5. Client Script Overrides Detail

### 5.1 Task-Accept Start.js (all task kinds)

| Override | Condition | Fields affected |
|---|---|---|
| Hide accepted_by | Always | `custom_accepted_by` |
| Subject not required | Always | `subject` reqd=0 |
| Hide subject | task_kind === "Order entry" | `subject` |
| Auto-set subject | Order entry + subject empty | subject = task name |
| Hide sidebar items | Always | like-action, form-assignments, form-tags, form-shared |
| Hide dashboard | Always | frm.dashboard.hide() |
| Show next_task_assign_to | Dispatch kinds + Acct Details: Entry | `custom_next_task_assign_to` |
| Hide next_task_assign_to | All others | `custom_next_task_assign_to` |
| Hide mobile clutter | Mobile only | `custom_accepted_at`, `custom_task_add_batch_no`, `custom_task_add_unit_price`, help boxes, timeline |
| Hide Account Details scanning | Acct Details: Entry | 6 scan/product fields, 9 section labels |
| Show Account Details photos | Acct Details: Entry | `custom_account_photos`, `status`, `priority` |
| Default Order accepting to Order entry | New task, task_kind === "Order accepting" | `task_kind` |
| Mobile CSS: hide header custom-actions | Mobile + Task form | Desktop custom button area |

### 5.2 Task-Account Details UI Cleanup.js (Account Details: Entry + Processing)

| Override | Fields affected |
|---|---|
| Hide product work section and all product fields | `custom_product_work_section`, `custom_task_product_summary`, 8 scanning fields |
| Hide all product/scanning labels by DOM | ~10 labels |
| Show `custom_account_photos` | photos field |
| Subject shown, reqd=0 | `subject` |
| Hide Products/Dispatch Work buttons and dropdown items | Desktop header buttons |
| Simplify status section: only status + priority | Extra columns hidden |
| Show custom photo box | Account photos UI |

### 5.3 Task-Other UI Cleanup.js (Other: Entry + Processing)

| Override | Fields affected |
|---|---|
| Show status, priority, barcode section | `status`, `priority`, `custom_barcode_section` |
| Subject shown, reqd=0 | `subject` |
| Hide product/scanning fields | ~15 fields including `other_items`, `other_budget`, `other_supplier` |
| Hide Products / Dispatch Work section | Section |
| Show next_task_assign_to conditionally | Shown if subject !== "Other: Processing" |

### 5.4 Task-Mobile Form Layout Fix.js (Pack on mobile)

| Override | Condition | Fields affected |
|---|---|---|
| Hide page title area | Pack + mobile | `.page-head .title-area` |
| Hide subject (aggressively) | Pack + mobile | `subject` field + label, inline style display:none |
| Hide core fields | Pack + mobile | `completed_at`, `task_kind`, `custom_assigned_to`, `custom_accepted_at` |
| Hide customer if empty | Pack + mobile + no value | `customer` |
| Force-show dispatch/product fields | Pack + mobile | `dispatch_case`, `custom_product_lines`, product work |

### 5.5 Task-Header Long Subject Fix.js (all task kinds)

| Override | Condition | Fields affected |
|---|---|---|
| Force subject visible | Always | `subject` hidden=0, DOM show |

**Conflict:** This script runs on every refresh and forces subject visible. Then `Task-Accept Start.js` hides it for Order entry. Then `Task-Mobile Form Layout Fix.js` hides it for Pack on mobile. The execution order matters and creates fragile behavior.

### 5.6 Task-Delivery UI Fix.js (Delivery only)

| Override | Fields affected |
|---|---|
| Show next_task_assign_to | `custom_next_task_assign_to` |

### 5.7 Task-Inspect Returns Next Assign Visible.js (Returns processing only)

| Override | Fields affected |
|---|---|
| Show next_task_assign_to | `custom_next_task_assign_to` |

### 5.8 Task-Lock Unaccepted.js (all task kinds)

| Override | Condition | Fields affected |
|---|---|---|
| All fields read_only=1 | Not accepted by current user & not admin | All non-break fields |
| Hide attach/grid buttons | Not accepted | .btn-attach, .btn-open, .grid-add-row, .grid-remove-rows |
| All fields read_only=0 | Accepted by current user or admin | All non-break fields + specific list of interactive fields |

### 5.9 Task-Lock Completed.js (all task kinds)

| Override | Condition | Fields affected |
|---|---|---|
| Entire form read-only | status === "Completed" | frm.set_read_only() |

---

## 6. Mobile-Specific Differences

### Pack / prepare items — Mobile vs Desktop

| Field | Desktop | Mobile |
|---|---|---|
| subject | V | **H** |
| task_kind | V | **H** |
| completed_at | V | **H** |
| customer | V | **H** (if empty) |
| custom_assigned_to | V | **H** |
| custom_accepted_at | V (hidden by separate rule) | **H** |
| Page title area | V | **H** |
| dispatch_case | V | V |
| product lines | V | V |
| product work section | V | V |

This is the most aggressive mobile hiding. Pack is optimized to show only the packing checklist on mobile, hiding almost all metadata. No other task kind does this.

### All task kinds — Mobile vs Desktop

| Element | Desktop | Mobile |
|---|---|---|
| custom_accepted_at | V | H (Task-Accept Start.js) |
| custom_task_add_batch_no | V | H (Task-Accept Start.js) |
| custom_task_add_unit_price | V | H (Task-Accept Start.js) |
| Help boxes | V | H (Task-Accept Start.js) |
| Timeline | V | H (Task-Accept Start.js) |
| Header custom buttons | V | H (CSS, replaced by floating buttons) |
| Sidebar (Like, Assign, Tags, Share) | V | H (hidden on all platforms actually) |

---

## 7. Server-Side Completion Gates

These are the actual requirements to complete a task. The UI does NOT currently prevent clicking Complete when these aren't met — the server rejects after the click.

| Task Kind | Gate | Field(s) checked | Error if not met |
|---|---|---|---|
| **All** | Acceptance required | `custom_accepted_by` | "Task must be accepted before changes" |
| **Order entry** | DC must be submitted | `dispatch_case` → DC.docstatus | "Dispatch Case must be submitted" |
| **Pack / prepare items** | Photo(s) attached | File attachments on task | "Attach at least one photo" |
| **Pack / prepare items** | All items packed | DC case_items status | "Not all items are packed" |
| **Delivery** | delivery_status = Delivered | `delivery_status` | "Cannot complete until delivered" |
| **Pickup Returns** | pickup_status = Returned to Warehouse | `pickup_status` | "Cannot complete until returned" |
| **Pickup Returns** | Photo before Returned to Warehouse | File attachments | "Attach photo before marking returned" |
| **Delivery** (no DC) | Photo required | File attachments | "Attach at least one photo" |
| **Return drop-off** (no DC) | Photo required | File attachments | "Attach at least one photo" |
| **Returns proc. / verification** | returned_qty on all items | DC case_items.returned_qty | "Set returned qty on all items" |
| **Invoice prep** | Sales Invoice submitted | `sales_invoice` → SI.docstatus | "Sales Invoice must be submitted" |
| **Discount Approval** | approval_outcome set | `approval_outcome` | "Set approval outcome" |
| **Debt Closure Approval** | Whitelisted users only | frappe.session.user | "Only authorized users may complete" |

---

## 8. Discrepancies and Inconsistencies

### 8.1 Critical — Fields visible where irrelevant

| # | Discrepancy | Affected task kinds | Root cause |
|---|---|---|---|
| 1 | **Product/scanning section visible on non-product tasks** | Purchase Approval, Write-off Approval, Debt Closure Approval, Distribute Payment, Payment Received, Return Call, Return to warehouse, Order accepting | `custom_product_work_section`, `custom_task_product_summary`, `custom_task_add_item_code`, `custom_task_add_qty` have no `depends_on`. Only Account Details and Other scripts hide them. |
| 2 | **custom_account_details_subject visible on ALL task kinds** | Every task kind | Field has no `depends_on`. Should be restricted to Account Details kinds. |
| 3 | **Barcode section visible on non-scanning tasks** | Purchase Approval, Write-off Approval, Debt Closure Approval, Distribute Payment, Payment Received | `custom_barcode_section` (Section Break) has no `depends_on`. Individual scan fields exclude Debt Collection only. |

### 8.2 Medium — Inconsistent core field behavior

| # | Discrepancy | Detail |
|---|---|---|
| 4 | **subject hidden only for Order entry** | Order entry auto-sets subject to task name and hides it. But Pack on mobile ALSO hides it. Desktop Pack shows subject. No other kind hides subject. |
| 5 | **Pack mobile hides 5 core fields that no other kind hides** | subject, task_kind, completed_at, customer, custom_assigned_to. This was done for screen space but creates a fundamentally different form for Pack vs all others on mobile. |
| 6 | **custom_next_task_assign_to shown by 4 different mechanisms** | Custom field depends_on (7 kinds), Task-Accept Start dispatch array (9 kinds), Task-Delivery UI Fix (1 kind), Task-Inspect Returns Next Assign Visible (1 kind). The dispatch array in Accept Start includes Discount Approval which is NOT in the custom field depends_on. |
| 7 | **Three scripts fight over subject visibility** | `Task-Header Long Subject Fix.js` forces visible. `Task-Accept Start.js` hides for Order entry. `Task-Mobile Form Layout Fix.js` hides for Pack mobile. Execution order determines winner. |

### 8.3 Low — Stale or wrong depends_on

| # | Discrepancy | Detail |
|---|---|---|
| 8 | **custom_account_photos depends_on uses wrong name** | `eval:doc.task_kind === "Account details"` — no such task_kind exists. Real values are "Account Details: Entry" and "Account Details: Processing". Field is only visible because client scripts force it. |
| 9 | **driver_handover_note: hidden=1 + depends_on** | The field is hidden=1 AND has depends_on excluding Order entry. The hidden=1 means it never shows regardless of depends_on. If it should show for some kinds, hidden must be 0. |
| 10 | **custom_account_details_section: fake depends_on** | `eval:doc.task_kind === "__never_show_account_details_documents__"` — intentionally never-matching expression. Should just be hidden=1 with no depends_on. |

### 8.4 Summary: custom_next_task_assign_to visibility conflicts

The "Next Task: Assign To" field has the most complex visibility logic. Here is the ACTUAL resulting visibility per task kind:

| Task Kind | CF depends_on | CS Accept Start | CS Delivery Fix | CS Returns Fix | CS Other Cleanup | **Net result** |
|---|---|---|---|---|---|---|
| Order entry | V | V | -- | -- | -- | **V** |
| Pack / prepare items | V | V | -- | -- | -- | **V** |
| Delivery | V | V | V | -- | -- | **V** |
| Return Call | V | V | -- | -- | -- | **V** |
| Pickup Returns | H | H | -- | -- | -- | **H** |
| Return drop-off | H | H | -- | -- | -- | **H** |
| Returns proc. / verification | V | H* | -- | V | -- | **V** (fix script wins) |
| Returns restocking | H | H | -- | -- | -- | **H** |
| Invoice prep | H | V* | -- | -- | -- | **V** (dispatch array wins) |
| Discount Approval | H | V* | -- | -- | -- | **V** (dispatch array wins) |
| Debt Collection | H | H | -- | -- | -- | **H** |
| Distribute Payment | H | H | -- | -- | -- | **H** |
| Payment Received | H | H | -- | -- | -- | **H** |
| Debt Closure Approval | H | H | -- | -- | -- | **H** |
| Purchase Approval | H | H | -- | -- | -- | **H** |
| Write-off Approval | H | H | -- | -- | -- | **H** |
| Account Details: Entry | H | V | -- | -- | -- | **V** |
| Account Details: Processing | H | H | -- | -- | -- | **H** |
| Other | H | H | -- | -- | H | **H** |
| Other: Entry | V | H | -- | -- | V | **V** |
| Other: Processing | V | H | -- | -- | V/H** | **V or H** |

`*` = Accept Start dispatch array includes this kind even though CF depends_on doesn't.
`**` = Other Cleanup shows it if subject !== "Other: Processing".

**Key conflict:** Invoice prep and Discount Approval are shown by Accept Start's dispatch array but NOT by the custom field depends_on. If the field's `depends_on` evaluates first (server-rendered), the field starts hidden, then the client script shows it — causing a flash.

---

## 9. Field Reference

### Permanently hidden fields (safe to ignore)

| Field | Reason |
|---|---|
| task_access_policy | Internal, hidden=1 |
| dispatch_group_id | Internal, hidden=1 |
| custom_account_details_entry_task | Internal, hidden=1 |
| custom_account_details_section | Intentionally hidden, fake depends_on |
| driver_handover_note | hidden=1 (likely needs review) |
| project, issue, type, color, is_group, task_weight, parent_task, is_template | Standard Frappe fields, hidden by property setters |

### Field order (from property setter field_order)

The canonical field order on the form is:
1. subject
2. task_access_policy (hidden)
3. completed_at
4. task_kind
5. custom_assigned_to
6. custom_next_task_assign_to
7. custom_accepted_by (hidden by CS)
8. custom_accepted_at
9. purchase_order
10. sales_order
11. customer
12. other_items, other_budget, other_supplier
13. sales_invoice
14. approval_outcome, approval_note
15. warehouse_pickup_photo, custom_delivery_photo, warehouse_dropoff_photo
16. driver_handover_note (hidden)
17. payment_entry
18. current_debt_amd, debt_threshold_amd
19. dispatch_group_id (hidden)
20. surgery_case, custom_select_surgical_kit_template
21. dispatch_case, dispatch_case_status
22. delivery_status, pickup_status
23. Products / Dispatch Work section
24. Barcode scanning section
25. return_pickup_driver, scheduled_return_date
26. Payment fields
27. Outstanding/credit/invoices/history
28. Standard fields (status, priority, etc.)
