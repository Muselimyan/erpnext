# ERPNext Expanded Playwright Test Catalog

## Purpose

This document lists future automated tests that can be added to the ERPNext Playwright regression suite so the system is tested at the level of its real business complexity.

The goal is not only to test that workflows complete, but also to test permissions, gates, data integrity, mobile/desktop UI, button labels, button size, button placement, visibility, duplicate controls, reports, workspaces, and known high-risk behaviors.

This is a planning document only. It does not change any existing test, server script, client script, or configuration.

## Source Documents Reviewed

Primary group audit documents:

- `deploy/test/work/group-1-dispatch-case-lifecycle.md`
- `deploy/test/work/group-2-task-system-and-gates-production-audit.md`
- `deploy/test/work/group-3-payments-debt-accounting-audit.md`
- `deploy/test/work/group-4-purchasing-flow-audit.md`
- `deploy/test/work/group-5-packing-barcode-scanning-analysis.md`
- `deploy/test/work/group-7-item-stock-management-audit.md`
- `deploy/test/work/group-9-ui-ux-mobile-audit.md`
- `deploy/test/work/group-10-reports-workspaces-config-audit.md`

Additional operational documents used for groups without dedicated audit files:

- `docs/06-items-variants-uoms.md`
- `docs/08-reorder-and-ordering-by-supplier.md`
- `docs/13-reporting-pack.md`
- `docs/16-unified-dispatch-flow.md`

## Test Suite Philosophy

Recommended test layers:

1. **API invariant tests** — fast tests for server behavior, gates, permissions, generated documents, and data state.
2. **Browser smoke tests** — desktop and mobile UI tests for buttons, fields, layout, visibility, labels, duplicate controls, clipped controls, console errors, and failed network requests.
3. **Full E2E tests** — slower end-to-end workflows proving complete business chains.
4. **Report/workspace tests** — verify that operational reports and workspaces exist, open, filter correctly, and show expected columns.
5. **Visual/layout tests** — dedicated screenshot and bounding-box assertions for mobile/desktop layout stability.
6. **Negative/security tests** — verify wrong roles cannot act, gates cannot be bypassed, and direct API calls are blocked where they should be blocked.

## Recommended Scale

This catalog was originally drafted when the suite had 19 tests. The implemented Playwright suite has since expanded; current discovered scope and run commands are documented in `tests/e2e/README.md`.

For long-term coverage planning, a mature suite would likely contain approximately:

| Group | Suggested Tests |
|---|---:|
| Group 1 — Dispatch Case Lifecycle | 25-35 |
| Group 2 — Task System and Gates | 30-45 |
| Group 3 — Payments, Debt, Accounting | 30-45 |
| Group 4 — Purchasing Flow | 20-30 |
| Group 5 — Packing and Barcode Scanning | 30-45 |
| Group 6 — Item Catalog, Variants, UOM | 15-25 |
| Group 7 — Item and Stock Management | 25-35 |
| Group 8 — Reorder and Supplier Ordering | 15-25 |
| Group 9 — UI/UX and Mobile | 35-60 |
| Group 10 — Reports, Workspaces, Config | 30-50 |
| Cross-Group Regression | 20-35 |

These targets do not include generated matrix cases.

---

# Group 1 — Dispatch Case Lifecycle

## API tests

1. Create Order Entry task and verify default assignment from policy.
2. Accept Order Entry task and verify accepted user, accepted time, and status.
3. Create Dispatch Case from Order Entry task and verify link back to task.
4. Call create Dispatch Case twice and verify idempotent existing-case return.
5. Add one product row and verify `case_items` fields.
6. Add multiple product rows and verify row order and quantities.
7. Complete Order Entry without Dispatch Case and verify rejection.
8. Complete Order Entry with unsubmitted Dispatch Case and verify rejection.
9. Complete Order Entry with submitted/valid Dispatch Case and verify Pack task creation.
10. Verify Pack task is linked to Dispatch Case `pack_task` field.
11. Complete Pack without pickup photo and verify rejection.
12. Complete Pack with pickup photo but unpacked items and verify rejection.
13. Mark one item packed and verify row status changes to Complete.
14. Mark all items packed and verify all row statuses are Complete.
15. Complete Pack and verify Dispatch Case status advances.
16. Complete Pack and verify Delivery task creation.
17. Verify delivery task assignment uses policy default team/user.
18. Set Delivery status directly to Delivered from Todo and verify rejection.
19. Set Delivery status to Picked Up and verify accepted state transition.
20. Set Delivery status to Delivered and verify task completion side effect.
21. No-return case: verify Invoice Preparation task is created after Delivered.
22. No-return case: verify generated stock movements are linked on Dispatch Case.
23. Return-expected case: verify delivery creates Return Call or documented current downstream task.
24. Return Call completion creates Pickup Returns task.
25. Pickup Returns status Picked Up creates return-pickup stock movement.
26. Pickup Returns status Returned to Warehouse creates Returns Inspection task.
27. Returns Inspection quantity reconciliation computes `used_qty` correctly.
28. Returns Inspection completion creates Returns Restocking when returned items exist.
29. Returns Restocking completion moves returned qty to Main warehouse.
30. Returns Inspection completion creates Invoice Preparation task.
31. Invoice Preparation completion without submitted Sales Invoice is rejected.
32. Invoice Preparation completion with submitted Sales Invoice advances to Payment Pending or Closed.
33. Debt Collection payment closes Dispatch Case only when fully paid.
34. Cancelled/aborted delivery creates Return to Warehouse task where applicable.
35. Submitted Dispatch Case fields are locked except allowed status/link fields.

## Browser tests

1. Order Entry task shows `Create Dispatch Case` button when no case exists.
2. Order Entry task shows `Open DC` or `View DC` when case exists.
3. `Create Dispatch Case` button text is exact on desktop.
4. `Create Dispatch Case` button text is exact on mobile.
5. Button is fully inside viewport on desktop.
6. Button is fully inside viewport on mobile.
7. No duplicate `Create Dispatch Case`, `Open DC`, or `View DC` buttons.
8. Dispatch Case form shows status and core header fields.
9. Dispatch Case item table is usable on desktop.
10. Dispatch Case item table is usable on mobile without hidden primary actions.
11. Discount case clearly shows awaiting approval state.
12. Pack task shows product work area.
13. Pack task product rows show item name, qty, packed status.
14. Delivery task shows delivery status controls.
15. Return Pickup task shows pickup status controls.
16. Returns Inspection task shows return quantity controls.
17. Invoice Preparation task shows invoice-related context to Accounting.
18. Completed Dispatch Case cannot be edited from UI.
19. Submitted Dispatch Case lock behavior is visible and consistent.
20. Console has no unexpected errors during each lifecycle page.

---

# Group 2 — Task System and Gates

## API tests

1. Every active Task Access Policy can be loaded.
2. Every supported task kind has exactly one policy record.
3. Default team user in every policy exists and is enabled or intentionally placeholder.
4. Allowed roles in every policy exist.
5. Creating each task kind sets `task_access_policy` correctly.
6. Creating each task kind assigns default team user correctly.
7. Accept each task kind as an allowed role.
8. Reject accept for each task kind as a wrong role.
9. Re-accept behavior is tested and documented: whether overwrite is allowed or blocked.
10. Accepted task can be edited by accepted user.
11. Accepted task cannot be edited by another user.
12. Accepted task cannot be completed by another user.
13. Unaccepted task cannot be completed.
14. Completed task cannot be edited by accepted user.
15. Completed task cannot be edited by Administrator/API user through normal API.
16. Completed task cannot be completed twice.
17. Reassignment through official reassignment path clears accepted user.
18. Reassignment resets status to Open.
19. Reassigned task can be accepted by new assignee/team member.
20. Simultaneous reassignment and completion is rejected.
21. Missing assignment behavior is tested against current deliberate policy.
22. Multiple assignment behavior is tested against current deliberate policy.
23. Account Details Entry completion creates Account Details Processing task.
24. Account Details Processing inherits customer/photos/description.
25. Other Entry completion creates Other Processing task.
26. Other Processing assignment follows policy/team rule.
27. Auto-escalation creates Director ToDos for overdue urgent tasks.
28. Auto-escalation creates Director ToDos for overdue normal tasks after threshold.
29. Auto-escalation does not duplicate ToDos for same task.
30. Auto-escalation leaves completed tasks alone.
31. Quick Entry creates Order Entry task with expected assignment.
32. `task_list_filtered` returns only allowed tasks for role.
33. `task_list_filtered` My Tasks filter includes accepted/assigned tasks.
34. `task_list_filtered` Open Tasks filter includes team queue tasks.
35. `task_list_filtered` Completed toggle includes completed only when requested.

## Browser tests

1. Unaccepted task shows `Accept / Start Task` button.
2. Accepted-by-current-user task hides `Accept / Start Task`.
3. Accepted-by-current-user task shows completion action when allowed.
4. Accepted-by-other-user task is read-only.
5. Completed task is read-only.
6. Completed task hides completion action.
7. Task fields controlled by TFV are visible/hidden per task kind.
8. Task fields controlled by TFE are editable/read-only per task kind and state.
9. No duplicate Accept buttons on each task kind.
10. `Complete` button text is exact.
11. `Accept / Start Task` button text is exact.
12. Button order is stable on desktop page header.
13. Button order is stable on mobile bottom action bar.
14. Buttons meet minimum touch size on mobile.
15. Buttons do not overlap title/header on long subject tasks.
16. Long subject is readable on desktop.
17. Long subject is readable on mobile.
18. Auto-reload does not refresh dirty forms.
19. Dirty form keeps unsaved user input for at least the auto-reload interval.
20. Task list mobile toggles show correct labels: My Tasks, Open Tasks, Completed.
21. Task list toggle state behaves consistently after navigation.
22. Back button appears on mobile Task form.
23. Back button does not appear on desktop.
24. Back button returns to Task list when appropriate.
25. Page has no unexpected console errors.

---

# Group 3 — Payments, Debt, and Accounting

## API tests

1. Debt Collection task contains linked open invoice rows.
2. Recording cash payment creates Payment Entry with Cash account.
3. Recording bank payment creates Payment Entry with Bank account.
4. Recording card payment creates Payment Entry with configured Bank/Card account.
5. Payment Entry references the correct Sales Invoice rows.
6. FIFO allocation uses Sales Invoice posting date, then invoice name.
7. Partial payment updates row paid/outstanding amounts correctly.
8. Full payment marks all relevant rows paid.
9. Overpayment is rejected or handled exactly as documented.
10. Payment history row is created and linked to Payment Entry.
11. Duplicate save with same payment amount does not create duplicate Payment Entry.
12. Debt Collection task closes only when total outstanding is zero.
13. Dispatch Case closes only after required payment state is complete.
14. Customer advance Payment Received task creates draft Payment Entry.
15. Customer advance Payment Entry is not auto-submitted.
16. Multiple advances accumulate Dispatch Case `prepaid_amount`.
17. Advance payment child table records each Payment Entry.
18. Latest advance quick-link updates to newest Payment Entry.
19. Debt Alert scheduler creates Director `Debt Alert` task when threshold exceeded.
20. Debt Alert scheduler updates existing open Debt Alert instead of duplicating.
21. Debt Alert scheduler does not create Finance Debt Collection task.
22. Debt Alert uses GL Entry net receivable.
23. Debt Closure Approval task uses policy default assignment.
24. Debt Closure Approval completion permission uses policy allowed roles.
25. Debt Closure profit calculates across multiple invoices.
26. Per-Dispatch Case profit is written correctly.
27. Payment Entry cancellation current manual-review behavior is asserted/documented.
28. Distribute Payment script remains disabled.
29. No Distribute Payment task appears after active payment flow.
30. Financial fields are hidden from non-financial roles by server permission.
31. Financial fields are visible to Accounting/Finance/Directors.
32. Pricing fields are visible to Order Creating plus financial roles.
33. Tender Agreement valid invoice submit updates supplied/remaining quantities.
34. Tender wrong-price invoice submit is blocked.
35. Tender over-supply invoice submit is blocked.
36. Duplicate active tender invoice submit is blocked.
37. Tender fulfillment audit rows are written on Sales Invoice submit.
38. Sales Invoice cancel reverses exactly recorded tender fulfillment rows.
39. Manually Closed Tender Agreement stays Closed after save.
40. Date-based tender status moves Draft/Active/Expired correctly.

## Browser tests

1. Debt Collection form shows open invoice table to Finance.
2. Finance sees payment amount/method/reference controls.
3. Non-Finance does not see or cannot edit payment controls.
4. Payment button/control labels are exact.
5. Payment table columns are visible and not clipped on desktop.
6. Payment table mobile layout remains readable.
7. Advance Payments section visible only to financial roles.
8. Profit fields visible only to financial roles.
9. Tender Agreement form shows supplied/remaining quantities clearly.
10. Tender validation errors are readable dialogs.
11. Debt Alert task is readable to Directors.
12. Debt Collection task is not confused with Debt Alert in UI labels.
13. Accounting user can open generated Sales Invoice from Dispatch Case.
14. Driver user cannot see financial fields on Dispatch Case.
15. Order Creating can see price/discount fields but not profit fields.

---

# Group 4 — Purchasing Flow

## API tests

1. Draft PO with Pending approval cannot be submitted.
2. Approved Draft PO can be submitted.
3. Editing approved PO header resets approval to Pending.
4. Editing approved PO item qty resets approval to Pending.
5. Editing approved PO item rate resets approval to Pending.
6. Non-material no-op save does not reset approval.
7. Purchase Approval task completion requires linked Purchase Order.
8. Purchase Approval task completion requires Approved/Rejected outcome.
9. Approved Purchase Approval writes approval fields to PO.
10. Rejected Purchase Approval writes rejection state/note to PO.
11. Purchase Receipt submit rejects warehouse other than Main - Inmed.
12. Purchase Receipt submit requires batch for tracked items when tracking enabled.
13. Purchase Receipt submit requires expiry for expiry-tracked batch items.
14. Purchase Invoice with `update_stock=1` is rejected.
15. Purchase Invoice without `update_stock` is allowed.
16. Reorder daily notification creates ToDo for low-stock items.
17. Reorder notification does not duplicate same-day ToDos.
18. Reorder notification text encoding is checked for correct em dash display.
19. Reorder query coverage handles more than 100 low-stock rows or documents limit.
20. Purchase Order one-supplier disabled safeguard is asserted as disabled/current decision.
21. Landed Cost Voucher flow creates expected accounting/valuation state if implemented.
22. Supplier prepayment allocation creates expected draft/submitted state.

## Browser tests

1. PO approval fields visible to Directors.
2. PO approval fields hidden/read-only for non-Directors where expected.
3. Submit button blocked with readable approval error.
4. Purchase Approval task shows approval outcome field.
5. Purchase Approval buttons have exact labels and are not duplicated.
6. PR barcode field visible and usable.
7. PR item grid displays warehouse, batch, expiry fields clearly.
8. PI `update_stock` warning/error is readable.
9. Purchasing workspace/report links open correctly.
10. Mobile PO/PR/PI forms have primary actions visible and not clipped.

---

# Group 5 — Packing and Barcode Scanning

## API tests

1. `dispatch_case_packing_scan` accepts direct Item Code barcode.
2. `dispatch_case_packing_scan` accepts Item Barcode child-table barcode.
3. `dispatch_case_packing_scan` accepts Batch barcode where applicable.
4. Unknown barcode is rejected with readable message.
5. Barcode for item not on Dispatch Case is rejected or warns exactly as designed.
6. Scan qty defaults to 1.
7. Scan qty > 1 increments scanned quantity correctly.
8. Scan qty cannot make row silently over-scanned without status indicating Over Scanned.
9. Partial scan sets status Partial and remaining qty correctly.
10. Complete scan sets status Complete and remaining qty zero.
11. Multiple rows for same item choose first incomplete row predictably.
12. GS1 barcode with AI 17 expiry and AI 10 lot parses expiry and lot.
13. GS1 parser handles parentheses format.
14. GS1 parser handles scanner prefix stripping.
15. FEFO warning appears when earlier-expiring batch exists.
16. Near-expiry warning appears when threshold applies.
17. FEFO warning does not hard-block packing when warning-only policy applies.
18. Packing problem status becomes Problem Open for incomplete/problem rows.
19. Packing problem ToDos are created for expected manager roles.
20. Packing problem alert does not duplicate after first alert.
21. Clearing all packing issues resets status to No Problem.
22. `task_mark_item_packed` true marks exactly the intended row complete.
23. `task_mark_item_packed` false resets exactly the intended row pending.
24. `task_mark_items_packed_batch` marks multiple intended rows.
25. Batch packed API rejects invalid row index.
26. Batch packed API rejects wrong task kind if enforced.
27. Packing APIs enforce role/session expectations or document current elevated-permission behavior.
28. Row reordering risk is tested by changing row order before index-based API call.
29. Dispatch Case save after packing preserves submitted document constraints.
30. Product add API initializes scanned/remaining/status fields correctly.

## Browser tests

1. Dispatch Case scan barcode field is visible.
2. Dispatch Case scan qty field is visible and defaults to 1.
3. Scan button label is exact.
4. Successful scan result message is visible and readable.
5. Warning scan result message is visible and readable.
6. Error scan result message is visible and readable.
7. Packing status columns are visible on desktop.
8. Packing status columns are usable on mobile.
9. Task product work area renders for Pack tasks.
10. Pack task checkboxes have minimum 22px touch size on mobile.
11. Pack task rows show item name and required quantity.
12. Pack task packed checkboxes update after click.
13. Pack task batch action does not duplicate buttons.
14. Pack mobile summary banner appears and is readable.
15. Mobile Add Pickup Photos button appears only for Pack task.
16. Mobile Add Drop-off Photos button appears only for Pickup Returns task.
17. Photo uploader restricts to images.
18. Photo preview thumbnails render after upload.
19. Fullscreen photo preview opens on thumbnail tap.
20. Fullscreen photo preview close button works.
21. Fullscreen zoom controls are visible and not clipped.
22. Compact return quantity view default is shown on phone.
23. Detailed return card view toggle works on phone.
24. Phone compact/detailed choice persists after reload.
25. Desktop returns table stays full table, not phone compact cards.

---

# Group 6 — Item Catalog, Variants, and UOM

## API tests

1. Item Code remains stable after transactional use where permissions allow edits.
2. Item Name contains enough variant detail for configured variant families.
3. Variant attributes are finite controlled values.
4. Variant item has supplier assignment according to one-item-one-supplier policy.
5. Item stock UOM is present.
6. Purchase UOM conversion factor is present when purchase UOM differs from stock UOM.
7. Sales UOM conversion factor is present when sales UOM differs from stock UOM.
8. Batch/expiry tracking flags match item category policy when tracking is enabled.
9. Serial tracking flags match instrument/tool category policy when tracking is enabled.
10. Non-stock service items do not appear in stock-picking workflows.
11. Item barcode uniqueness is enforced.
12. Item search by code finds exact item.
13. Item search by name finds expected item.
14. Similar variants are distinguishable in search result display.
15. Pack-breaking policy field exists and saves expected values.
16. Legacy 1C code field exists and is protected/documented according to current policy.
17. Disabled item does not appear in add-product dialogs.
18. Item group hierarchy supports expected top-level categories.
19. Item can be grouped by supplier for reorder reports.
20. Decimal quantity behavior is rejected or allowed according to UOM policy.

## Browser tests

1. Item list search by item code works.
2. Item list search by item name works.
3. Item form shows Item Code, Item Name, Item Group, Stock UOM.
4. Variant attributes visible where relevant.
5. Barcode child table visible to allowed roles.
6. UOM conversion table visible to allowed roles.
7. Item field labels are readable on mobile.
8. Item form primary actions not clipped on mobile.
9. Long item names do not break list row layout.
10. Disabled items have clear disabled indicator.

---

# Group 7 — Item and Stock Management

## API tests

1. Customer governance script binding is verified: reference DocType should be Customer if active.
2. Non-privileged user cannot change `client_code` when governance is active.
3. Privileged user can change `client_code` when allowed.
4. Non-privileged user cannot uncheck provisional status.
5. Privileged user can approve provisional customer.
6. FEFO Stock Entry warning script enabled/disabled state is asserted according to current decision.
7. Stock Entry with fresher batch while older batch exists produces warning when FEFO enabled.
8. Near-expiry batch produces warning when FEFO enabled.
9. Client warehouse guard enabled/disabled state is asserted according to current decision.
10. Standard sale stock movement into client warehouse is rejected when guard enabled.
11. Direct stock movement into client warehouse is tested/documented.
12. Collection Set readiness validator fires once, not twice.
13. Collection Set readiness Ready state when all projected qty sufficient.
14. Collection Set readiness Short state when non-critical shortage exists.
15. Collection Set readiness Critical Short when critical shortage exists.
16. Collection Set duplicate warning messages do not appear.
17. Surgical Kit Template vs Collection Set source-of-truth behavior is tested.
18. Dispatch Case template selection uses current intended template DocType.
19. Add-product API rejects unauthorized role or documents current elevated behavior.
20. Item lookup barcode API resolves simple barcodes.
21. Item lookup barcode API rejects unknown barcodes.
22. Item selection dialog escapes item names safely.
23. Item selection dialog handles names with quotes/special characters.
24. Stock Balance for Main decreases after dispatch stock movement.
25. Stock Balance for Delivery In-Transit increases after pack.
26. Stock Balance for Delivery In-Transit decreases after delivery.
27. Return Pickup In-Transit balances move correctly during pickup.
28. Returns warehouse balances move correctly after drop-off.
29. Main warehouse increases after restocking returned quantity.
30. Negative stock report detects intentionally-created test negative only in isolated test data.

## Browser tests

1. Customer form shows client code/provisional fields to allowed roles.
2. Customer governance error messages are readable.
3. Dispatch Case template Link field shows intended DocType records.
4. Template autofill replaces rows and warning/confirmation behavior is documented/tested.
5. Add Items by Category button label is exact.
6. Search & Add Item button label is exact.
7. Item category modal opens and fits desktop viewport.
8. Item category modal opens and fits mobile viewport.
9. Search modal result rows show item code, item name, and rate.
10. Dialog buttons are not clipped on mobile.
11. Special-character item names render safely.
12. Collection Set readiness warning appears once.
13. Stock Entry FEFO warning message appears when expected.
14. Stock Entry warehouse guard error appears when expected.
15. Relevant stock reports open from UI.

---

# Group 8 — Reorder and Supplier Ordering

## API tests

1. Reorder report calculates sellable on-hand from Main - Inmed.
2. Reorder report excludes client location stock from sellable availability.
3. Reorder report excludes Return Pickup In-Transit from sellable availability.
4. Reorder report excludes Returns warehouse from sellable availability.
5. Reorder report includes expected inbound supply from approved/open POs where intended.
6. Reorder report accounts for committed demand where implemented.
7. Low-stock item appears when below threshold.
8. Item at threshold behavior is exact: appears or does not appear according to policy.
9. Item above threshold does not appear.
10. Suggested quantity follows Min/Max rule where configured.
11. Suggested quantity follows ROP/reorder qty rule where configured.
12. Variant thresholds are evaluated on variant item, not template.
13. One item to one supplier invariant is tested.
14. PO generated/prepared per supplier contains only that supplier's items.
15. Supplier change requires governance/change reason if implemented.
16. Reorder threshold change requires `reorder_change_reason`.
17. Saving without threshold change does not require reason.
18. Reorder notification recipients include Purchasing and Directors.
19. Reorder notification skips disabled users.
20. Reorder notification handles more than 100 low-stock items according to documented limit.

## Browser tests

1. Search for `RPT - Purchasing - Norm and Reorder` and open report.
2. Report shows item, supplier, available qty, reorder level, suggested qty.
3. Report can be filtered/grouped by supplier.
4. Low-stock rows are readable on mobile.
5. Buyer can open Item from report row.
6. Buyer can open Supplier from report row where supported.
7. Reorder change reason field visible when editing Item reorder table.
8. Missing reason error is readable.
9. Purchasing workspace includes reorder report shortcut.
10. Report does not horizontally clip primary columns on laptop/mobile.

---

# Group 9 — UI/UX and Mobile

## Form/button tests

1. Every Task kind opens on desktop with no console errors.
2. Every Task kind opens on mobile with no console errors.
3. Every Task kind has no failed `/api/` requests on load.
4. Desktop page header buttons are not duplicated.
5. Mobile bottom action bar buttons are not duplicated.
6. Mobile subheader buttons are not duplicated.
7. All primary action buttons have exact expected text.
8. All primary action buttons meet minimum width and height.
9. Buttons do not overlap each other.
10. Buttons do not overlap the Task title.
11. Buttons do not go outside viewport.
12. Buttons remain visible after save.
13. Buttons remain visible after refresh.
14. Buttons remain visible after route navigation back/forward.
15. Long Task subject truncates gracefully in header.
16. Long Task subject is readable in form body or summary.
17. Subject field visible where expected on desktop.
18. Subject field visible or intentionally hidden/replaced where expected on mobile.
19. `task_kind` visibility tested per desktop/mobile and per task kind.
20. `custom_assigned_to` visibility tested per desktop/mobile and per task kind.
21. `custom_accepted_by` visibility tested per desktop/mobile and per task kind.
22. `dispatch_case` visibility tested per desktop/mobile and per task kind.
23. `customer` visibility tested per desktop/mobile and per task kind.
24. No field appears as blank whitespace-only layout gap.
25. No section consumes full width incorrectly.
26. No horizontal scroll on mobile except approved tables.
27. Mobile scroll starts at top on new Task navigation.
28. Mobile does not scroll to top on same-task auto-refresh if user is editing.
29. Touch targets are at least 44px where practical for primary mobile controls.
30. Form remains usable at 375x812 viewport.
31. Form remains usable at very small mobile height viewport.
32. Form remains usable at tablet width.
33. Browser zoom/responsive resize does not duplicate buttons.
34. Back button appears once on mobile Task form.
35. Back button does not appear on desktop.
36. Back button fallback goes to Search for `Task` and open the Task list.
37. Back button does not navigate out of ERPNext unexpectedly.
38. Back button touch feedback resets after tap/drag.
39. Mobile list filter toggles render once.
40. Mobile list Refresh button renders once.
41. Mobile list filters persist or reset according to documented decision.
42. Native Frappe filters can coexist with custom toggles, or conflict is documented.
43. The `...` menu tooltip removal does not break the menu.
44. Page action compaction does not hide important buttons.
45. Delivery mobile UI shows `custom_next_task_assign_to` where expected.
46. Delivery mobile buttons wrap without clipping.
47. Pack mobile UI hides only intended metadata fields.
48. Pack mobile UI keeps dispatch case/product fields visible.
49. Photo preview grid has no clipped thumbnails.
50. Fullscreen photo viewer works with close/reset/zoom controls.

## Visual snapshot tests

1. Task form desktop baseline screenshot per task kind.
2. Task form mobile baseline screenshot per task kind.
3. Task list desktop baseline screenshot.
4. Task list mobile baseline screenshot.
5. Dispatch Case desktop baseline screenshot.
6. Dispatch Case mobile baseline screenshot.
7. Pack task mobile compact screenshot.
8. Returns inspection mobile compact screenshot.
9. Returns inspection mobile detailed screenshot.
10. Long subject mobile screenshot.

---

# Group 10 — Reports, Workspaces, and Configuration

## Report existence/opening tests

1. Every official report in Reporting Pack exists.
2. Every official report opens without server error.
3. Every official report has expected reference DocType.
4. Every official report has expected role permissions.
5. Duplicate report pairs are detected and classified official vs legacy/deferred.
6. Missing KPI dashboard reports are asserted as missing/current gap or implemented later.
7. Company-specific `- Inmed` report variants exist where expected.
8. Legacy Surgery Case report remains classified legacy.
9. Disabled/deferred Distribute Payment report/task state remains consistent.
10. Report SQL does not expose restricted fields to wrong roles.

## Report content tests

1. `RPT - Stock - Client Locations (All)` shows only client-location warehouse stock.
2. `RPT - Stock - Delivery In-Transit - Inmed` filters Delivery In-Transit only.
3. `RPT - Stock - Return Pickup In-Transit - Inmed` filters Return Pickup In-Transit only.
4. `RPT - Stock - Returns - Inmed` filters Returns only.
5. `RPT - Stock - In-Transit Stuck (Age Check)` shows old in-transit records.
6. `RPT - Stock - Batch and Expiry Balance` shows batch/expiry columns.
7. `RPT - Stock - Expiry Classification` classifies expired/near/ok correctly.
8. `RPT - Sales - Sold Items Detail` shows submitted invoice lines.
9. `RPT - Sales - History by Client` filters by customer.
10. `RPT - Sales - Top Customers` sorts by revenue descending.
11. `RPT - Sales - Top Products` sorts by quantity/revenue as documented.
12. `RPT - Price Override List` shows active special prices.
13. `RPT - Accounting - Debt Status Board` includes unpaid/semi-paid invoices.
14. `RPT - Receivables - Unpaid Invoices (Aging)` shows aging buckets.
15. `RPT - Receivables - Unallocated Advances` shows unallocated Payment Entries.
16. `RPT - Risk - Debt Threshold Exceeded` uses net receivable logic.
17. `RPT - Dispatch Cases - Aging (Open)` shows open cases by status.
18. `RPT - Ops - Driver Task Queue (Derived)` shows driver assignments.
19. `RPT - Purchasing - Norm and Reorder` shows low-stock purchasing signal.
20. `RPT - Data Quality - Negative Stock` catches negative Bin rows.
21. `RPT - Data Quality - Tracked Items Missing Identifiers` catches missing batch/serial.
22. `RPT - Returns - Refund Queue` opens and filters correctly.
23. `RPT - Low Stock by Supplier` groups by supplier.
24. Report filters are usable on desktop.
25. Report filters are usable on mobile.

## Workspace/config tests

1. `Dispatch - Task Queues` workspace exists.
2. Dispatch workspace has Pack Tasks shortcut.
3. Dispatch workspace has Delivery Tasks shortcut.
4. Dispatch workspace has Return Pickup Tasks shortcut.
5. Dispatch workspace has Returns Inspection Tasks shortcut.
6. Dispatch workspace has Invoice Tasks shortcut.
7. Dispatch workspace has Debt Collection Tasks shortcut.
8. Every workspace shortcut opens the intended DocType/report.
9. Workspace shortcuts apply expected filters.
10. `Management - KPI Dashboard` skeleton/gap is asserted or later completed.
11. `Ops - Reporting Pack` workspace contains official report shortcuts.
12. Workspace cards/buttons are visible on desktop.
13. Workspace cards/buttons are visible on mobile.
14. Custom property setters are inventoried and match documentation.
15. Role profiles are inventoried and custom-role gap is asserted/documented.
16. Notifications are inventoried and InMED notification gap is asserted/documented.
17. Superseded `Surgery Case Workflow` active state is asserted/documented.
18. IRS 1099 print format irrelevant status is asserted/documented.
19. Report permissions prevent wrong role access.
20. Report permissions allow expected role access.

---

# Cross-Group Tests

## End-to-end workflows

1. Full no-return Dispatch Case: Order Entry → Pack → Delivery → Invoice → Debt Collection → Payment → Closed.
2. Full return-expected Dispatch Case: Order Entry → Pack → Delivery → Return Call → Pickup Returns → Returns Inspection → Restock → Invoice → Payment → Closed.
3. Discounted no-return Dispatch Case: discount request → Director approval → Pack → Delivery → Invoice.
4. Discount rejection path: discount request → Director rejection → revision Order Entry → corrected Dispatch Case.
5. Prepaid Dispatch Case: advance payment → dispatch → invoice applies advance → closes or creates remaining Debt Collection.
6. Partial payment Dispatch Case: invoice → partial Debt Collection payment → stays Payment Pending.
7. Multi-invoice Debt Collection: one payment allocates FIFO across multiple invoices.
8. Tender-priced Dispatch Case: invoice rate matches tender and decrements tender quantities.
9. Tender cancellation: submitted invoice decrements tender, cancel reverses tender.
10. Return case with lost/damaged qty: verifies manual-review/deferred billing behavior.
11. Aborted delivery/cancelled case: stock returns to correct warehouse and task is created.
12. Low-stock after dispatch: reorder report includes item after stock drops below threshold.
13. Purchasing recovery: low-stock item leads to PO approval, PR receipt, stock replenishment.
14. Customer debt threshold: unpaid invoice triggers Debt Alert, then payment removes/updates alert state.
15. Mobile-only operational flow: accept Pack task, upload photo, mark packed, complete.
16. Desktop-to-mobile handoff: task accepted on desktop, opened on mobile, state consistent.
17. Concurrent user behavior: two users open same task, one accepts, other loses edit rights.
18. Concurrent duplicate action protection: double-click complete/create buttons does not duplicate downstream records.
19. Refresh/reload during save does not create duplicate tasks/documents.
20. Network retry/slow response does not duplicate payments, tasks, or stock entries.

## Safety and environment tests

1. BASE_URL production URL is rejected.
2. Non-HTTPS URL is rejected.
3. Unknown host is rejected.
4. Missing API credentials fail fast without printing secrets.
5. Missing role credentials fail fast without printing secrets.
6. Reports/artifacts do not contain API secret or password values.
7. `.env.local` remains gitignored.
8. Sessions directory remains gitignored.
9. Test artifacts remain gitignored.
10. Test data names include run identifiers where possible.

---

# Suggested Implementation Order

## Phase 1 — Make the current suite sharper

1. Add preflight tests for environment, credentials, policies, users, and required master data.
2. Expand current Task form smoke test into a task-kind matrix.
3. Add button label/size/position checks for desktop and mobile.
4. Add report/workspace existence tests.
5. Wire run manifest for created records.

## Phase 2 — Cover the complete business chain

1. Complete no-return financial E2E through Payment Entry and Closed Dispatch Case.
2. Add return-expected full E2E.
3. Add stock movement integrity checks for all Dispatch Case stages.
4. Add invoice/payment/tender integrity checks.
5. Add cleanup/manual review manifest for generated test data.

## Phase 3 — Cover high-risk known audit findings

1. Task re-acceptance behavior.
2. Multiple Accept button detection for all relevant task kinds.
3. Payment/debt/tender regression suite.
4. Packing barcode/GS1/FEFO suite.
5. Customer governance and stock safeguard state assertions.
6. UI/mobile scripts performance and duplication checks.

## Phase 4 — Mature regression infrastructure

1. Nightly API tests.
2. Manual or scheduled smoke tests on desktop/mobile.
3. Full E2E before release only.
4. HTML/trace/report artifact publishing.
5. Visual snapshot review for mobile/desktop UI.

## Ready for New Task Kinds

I am ready to define new Playwright task kinds/spec files from this catalog whenever you say to proceed.

Recommended first new test categories:

1. `tests/e2e/tests/preflight/environment-and-master-data.spec.ts`
2. `tests/e2e/tests/smoke/task-form-matrix.spec.ts`
3. `tests/e2e/tests/smoke/mobile-layout-and-buttons.spec.ts`
4. `tests/e2e/tests/api/task-policy-matrix.spec.ts`
5. `tests/e2e/tests/api/payments-debt-accounting.spec.ts`
6. `tests/e2e/tests/api/packing-barcode.spec.ts`
7. `tests/e2e/tests/reports/reports-and-workspaces.spec.ts`
8. `tests/e2e/tests/e2e/no-return-full-financial-close.spec.ts`
9. `tests/e2e/tests/e2e/return-expected-full-path.spec.ts`
