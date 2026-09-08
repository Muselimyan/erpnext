# Group 3 Smoke Test

**Scope:** Payments, Debt, Tender, and Accounting fixes deployed to TEST.

**Environment:** `https://test.erpnext.am` only.

**Status before starting:** Group 3 is deployed to TEST and check-mode verified. This manual is for functional smoke testing before prod promotion.

**Do not use prod data or prod URL for this test.**

---

## 0. General testing rules

1. Test only on `https://test.erpnext.am`.
2. Use controlled test customers, items, tenders, invoices, and tasks where possible.
3. Write down every document name created during testing:
   - Customer
   - Item
   - Dispatch Case
   - Task
   - Sales Invoice
   - Payment Entry
   - Tender Agreement
4. If a step fails, stop that test section and record:
   - Section number
   - Logged-in user
   - Document name
   - Expected result
   - Actual result/error message
5. Do not manually correct failed records before recording the failure.
6. A section passes only when the expected system behavior is observed in ERPNext, not only because the script exists.

---

## 1. Debt Collection payment flow

**Covers fixes:** B-01, B-11, B-12

**Purpose:** Confirm Debt Collection payments create invoice-referenced Payment Entries, allocate by FIFO posting date, and use the correct cash/bank account.

### Roles/users

- `Ops - Finance` for Debt Collection task/payment entry recording.
- `Ops - Accounting` or System Manager for checking Sales Invoice/Payment Entry accounting details if Finance cannot open the needed screen.

### Required test data

Prepare or find:

1. One test Customer with at least two submitted unpaid Sales Invoices.
2. The two Sales Invoices must have different posting dates.
3. A Debt Collection task for that Customer with `open_invoices` rows populated and linked to those Sales Invoices.

Recommended controlled setup:

- Invoice A: older posting date, outstanding amount > 0.
- Invoice B: newer posting date, outstanding amount > 0.
- Payment amount: enough to fully pay Invoice A and partially pay Invoice B.

### Steps

1. Login to TEST as an `Ops - Finance` user.
2. Search **Task**.
3. Open the Debt Collection task for the test Customer.
4. Confirm `task_kind = Debt Collection`.
5. In the Open Invoices table, confirm each payable row has:
   - `sales_invoice` filled.
   - `outstanding_amount > 0`.
6. Enter `new_payment_amount` equal to:
   - full outstanding of the oldest invoice, plus part of the next invoice.
7. Set `payment_method_dc = Cash`.
8. Fill `payment_reference_dc` with a clear test reference, e.g. `G3-SMOKE-CASH-001`.
9. Save the task.
10. Confirm the script clears `new_payment_amount` after processing.
11. Open the created Payment Entry.
12. Confirm Payment Entry is submitted.
13. Confirm Payment Entry has Sales Invoice references in its References table.
14. Confirm allocation order:
    - Older posting-date invoice paid first.
    - Remaining amount allocated to the newer invoice.
15. Confirm `paid_to = Cash - Inmed`.
16. Return to the Debt Collection task.
17. Confirm payment history/open invoice rows reflect the payment.
18. Repeat with a second payment using `payment_method_dc = Bank Transfer` or `Card`.
19. Confirm the second Payment Entry uses `paid_to = Bank - Inmed`.
20. If final payment clears all outstanding amounts, confirm:
    - `total_outstanding = 0`.
    - Debt Collection task completes or moves to the expected closure path.
    - Dispatch Case status updates according to the current flow.

### Pass conditions

- Payment Entry is created and submitted for Debt Collection payments.
- Payment Entry references the Sales Invoices.
- Allocation uses Sales Invoice posting date, not invoice name.
- Cash payment posts to `Cash - Inmed`.
- Bank Transfer/Card posts to `Bank - Inmed`.
- No `Distribute Payment` task is created.
- Outstanding values decrease correctly.

### Fail conditions

- Payment Entry has no Sales Invoice references.
- Allocation is by invoice name instead of posting date.
- Bank Transfer/Card posts to `Cash - Inmed`.
- Payment creates or expects a `Distribute Payment` task.
- Debt Collection task totals do not update after save.
- Save fails with a Server Script error such as `NameError`, `SyntaxError`, or permission/mandatory-field error.

### Troubleshooting notes

- If save fails with `NameError: name 'invoice_dates' is not defined`, the TEST server still has an old unsafe FIFO script. Redeploy `Task-before-save-payment-recording.py`, clear TEST cache, and retry. The corrected script must not use `lambda`, `invoice_dates`, or generator-based `sum(... for ...)` for the FIFO/payment section.

### TEST result — 2026-09-07

- Tester saved `TASK-2026-00539` with `new_payment_amount = 5,000,000`, `payment_method_dc = Cash`, and `payment_reference_dc = G3-SMOKE-CASH-001`.
- Payment Entry `ACC-PAY-2026-00007` was created and submitted.
- `paid_to = Cash - Inmed`.
- References were created correctly:
  - `ACC-SINV-2026-00008` allocated `4,680,000`.
  - `ACC-SINV-2026-00015` allocated `320,000`.
- Task outstanding values updated correctly:
  - `ACC-SINV-2026-00008` outstanding `0`.
  - `ACC-SINV-2026-00015` outstanding `1,240,000`.
  - `total_outstanding = 1,240,000`.
- Follow-up found and fixed on TEST: the first task Payment History row captured amount/method/reference but did not populate the `payment_entry` link. The server script was patched to set the appended child row's `payment_entry` directly after Payment Entry submit.
- Second payment test used `payment_method_dc = Bank Transfer`, `payment_reference_dc = G3-SMOKE-BANK-001`, amount `1,240,000`.
- Payment Entry `ACC-PAY-2026-00008` was created and submitted with `paid_to = Bank - Inmed`.
- Second Payment Entry reference:
  - `ACC-SINV-2026-00015` allocated `1,240,000`.
- Task completed with `total_outstanding = 0`.
- Payment History links verified:
  - `G3-SMOKE-CASH-001` -> `ACC-PAY-2026-00007`.
  - `G3-SMOKE-BANK-001` -> `ACC-PAY-2026-00008`.

---

## 2. Customer advance payment flow

**Covers fixes:** B-03, B-12

**Purpose:** Confirm customer advances create draft Payment Entries, append Dispatch Case advance audit rows, and accumulate prepaid amount instead of overwriting it.

### Roles/users

- `Ops - Finance` for Payment Received task.
- `Ops - Accounting` or System Manager for checking Payment Entry if required.

### Required test data

Prepare or find:

1. One test Customer.
2. One linked Dispatch Case for that Customer.
3. No Sales Invoice is required for this advance test.

### Steps

1. Login to TEST as `Ops - Finance`.
2. Search **Task**.
3. Create or open a `Payment Received` task for the test Customer.
4. Link the Dispatch Case if the task has the `dispatch_case` field available.
5. Enter advance amount, e.g. `10000`.
6. Set payment method to `Cash`.
7. Set payment reference to `G3-SMOKE-ADV-CASH-001`.
8. Complete the task.
9. Open the created Payment Entry.
10. Confirm Payment Entry is draft, not submitted.
11. Confirm `paid_to = Cash - Inmed`.
12. Open the linked Dispatch Case.
13. Confirm the `advance_payments` child table has a row with:
    - payment date
    - amount
    - method
    - reference
    - Payment Entry
    - source task
14. Confirm `prepaid_amount` equals the sum of all rows in `advance_payments`.
15. Confirm `prepaid_payment_entry` points to the latest created advance Payment Entry.
16. Create a second `Payment Received` task for the same Customer/Dispatch Case.
17. Use method `Bank Transfer` or `Card`.
18. Complete it.
19. Confirm second Payment Entry is draft and uses `paid_to = Bank - Inmed`.
20. Reopen the Dispatch Case.
21. Confirm:
    - A second `advance_payments` row was appended.
    - `prepaid_amount` increased by the second amount.
    - First row was not overwritten.

### Prepared TEST data — 2026-09-07

- Payment Received task: `TASK-2026-00543`.
- Direct URL: `https://test.erpnext.am/app/task/TASK-2026-00543`.
- Dispatch Case: `DC-2026-00144`.
- Customer: same D143 customer as Section 1.
- Assigned/accepted user: `levonaghinyan77@gmail.com`.
- Baseline Dispatch Case values before Section 2:
  - `prepaid_amount = 0`.
  - `prepaid_payment_entry` empty.
  - `advance_payments` row count `0`.
- `Task-after-save-advance-payment.py` was patched on TEST before smoke testing to avoid RestrictedPython risks: `frappe.utils.today()` is used explicitly, and prepaid total is calculated with a plain loop instead of generator-based `sum(... for ...)`.

Recommended first test values:

- `new_payment_amount = 10000`.
- `payment_method_dc = Cash`.
- `payment_reference_dc = G3-SMOKE-ADV-CASH-001`.

### TEST result — 2026-09-07

- First Payment Received task `TASK-2026-00543` completed with `new_payment_amount = 10000`, `payment_method_dc = Cash`, `payment_reference_dc = G3-SMOKE-ADV-CASH-001`.
- Created Payment Entry `ACC-PAY-2026-00009`:
  - `docstatus = 0` / Draft.
  - `paid_amount = 10,000`.
  - `paid_to = Cash - Inmed`.
  - no Sales Invoice references.
- Second Payment Received task `TASK-2026-00544` completed with `new_payment_amount = 20000`, `payment_method_dc = Bank Transfer`, `payment_reference_dc = G3-SMOKE-ADV-BANK-001`.
- Created Payment Entry `ACC-PAY-2026-00010`:
  - `docstatus = 0` / Draft.
  - `paid_amount = 20,000`.
  - `paid_to = Bank - Inmed`.
  - no Sales Invoice references.
- Dispatch Case `DC-2026-00144` accumulated advances correctly:
  - `prepaid_amount = 30,000`.
  - `prepaid_payment_entry = ACC-PAY-2026-00010`.
  - `advance_payments` row 1: `10,000`, Cash, `G3-SMOKE-ADV-CASH-001`, `ACC-PAY-2026-00009`, source task `TASK-2026-00543`.
  - `advance_payments` row 2: `20,000`, Bank Transfer, `G3-SMOKE-ADV-BANK-001`, `ACC-PAY-2026-00010`, source task `TASK-2026-00544`.
- Section 2 passed on TEST.

### Pass conditions

- Advance Payment Entry is created as draft.
- Cash maps to `Cash - Inmed`.
- Bank Transfer/Card maps to `Bank - Inmed`.
- Dispatch Case `advance_payments` table records each advance separately.
- `prepaid_amount` accumulates from all child rows.
- `prepaid_payment_entry` is only the latest quick reference.

### Fail conditions

- Payment Entry auto-submits for an advance.
- `advance_payments` row is missing.
- Second advance overwrites the first.
- `prepaid_amount` equals only the latest payment instead of total payments.

---

## 3. Tender submit flow

**Covers fixes:** B-04, B-05, B-13, tender price validation

**Purpose:** Confirm tender matching is hospital-only, tender price is enforced, oversupply is blocked, duplicate active tender rows are blocked, tender quantities update correctly, and fulfillment audit rows are written.

### Roles/users

- `Ops - Accounting` for Sales Invoice submit.
- `Ops - Directors` or System Manager for creating/adjusting Tender Agreement records if needed.

### Required test data

Prepare:

1. One hospital Customer.
2. One Item.
3. One active Tender Agreement for that hospital and item.
4. Tender Agreement Item fields:
   - `item_code` = test item
   - `won_quantity` = controlled quantity, e.g. `10`
   - `supplied_quantity` = `0` or known value
   - `tender_price` = known value, e.g. `5000`
5. One draft Sales Invoice for the hospital Customer with the same item.

### Prepared TEST data — 2026-09-08

Section 3 uses Tender Agreement and Sales Invoice records, not Task records.

- Customer/Hospital: `G3-SMOKE-HOSPITAL-001 - Inmed`.
- Item: `3146-60450`.
- Tender Agreement: `G3 Section 3 Smoke Tender 2026-09-08`.
- Tender values:
  - `status = Active`.
  - `valid_from = 2026-09-01`.
  - `valid_to = 2026-12-31`.
  - `tender_price = 390,000`.
  - `won_quantity = 10`.
  - `supplied_quantity = 0`.
  - `remaining_quantity = 10`.
- Draft Sales Invoices:
  - Test A valid invoice: `ACC-SINV-2026-00016`, qty `2`, rate `390,000`.
  - Test B wrong-price invoice: `ACC-SINV-2026-00017`, qty `1`, rate `400,000`.
  - Test C oversupply invoice: `ACC-SINV-2026-00018`, qty `20`, rate `390,000`.

### Test A — correct tender price passes

1. Open the draft Sales Invoice.
2. Set item quantity within remaining tender quantity, e.g. `2`.
3. Set item rate exactly equal to `Tender Agreement Item.tender_price`.
4. Submit the Sales Invoice.
5. Open the Tender Agreement.
6. Confirm `supplied_quantity` increased by the invoice quantity.
7. Confirm `remaining_quantity = won_quantity - supplied_quantity`.
8. Reopen the Sales Invoice.
9. Confirm `tender_fulfillments` table has a row recording:
   - Tender Agreement
   - Item Code
   - Quantity
   - Sales Invoice Item
   - Applied At

### Test B — wrong tender price is blocked

1. Create another draft Sales Invoice for the same hospital/item.
2. Set quantity within remaining tender quantity.
3. Set item rate different from tender price.
4. Try to submit.
5. Confirm submit is blocked.
6. Confirm the error says the invoice rate must equal tender price.
7. Confirm Tender Agreement `supplied_quantity` did not change.

### Test C — oversupply is blocked

1. Create another draft Sales Invoice for the same hospital/item.
2. Set rate equal to tender price.
3. Set quantity greater than remaining tender quantity.
4. Try to submit.
5. Confirm submit is blocked.
6. Confirm the error says the tender has only the remaining quantity available.
7. Confirm Tender Agreement `supplied_quantity` did not change.

### Test D — duplicate active tender is blocked

1. Create or temporarily activate a second Tender Agreement for the same hospital/item.
2. Create a draft Sales Invoice for that hospital/item.
3. Set rate/quantity otherwise valid.
4. Try to submit.
5. Confirm submit is blocked with duplicate active Tender Agreements message.
6. Close or expire the duplicate tender after the test.

### TEST result — 2026-09-08

- Test A valid invoice `ACC-SINV-2026-00016` submitted successfully.
  - Tender `supplied_quantity` changed from `0` to `2`.
  - Tender `remaining_quantity` changed from `10` to `8`.
  - Sales Invoice `tender_fulfillments` row was written for Tender Agreement `G3 Section 3 Smoke Tender 2026-09-08`, item `3146-60450`, quantity `2`.
- Test B wrong-price invoice `ACC-SINV-2026-00017` was blocked with the expected tender-price message.
  - Invoice stayed Draft.
  - No tender fulfillment rows were written.
  - Tender quantities remained `supplied_quantity = 2`, `remaining_quantity = 8`.
- Test C oversupply invoice `ACC-SINV-2026-00018` was blocked with the expected remaining-quantity message.
  - Invoice stayed Draft.
  - No tender fulfillment rows were written.
  - Tender quantities remained `supplied_quantity = 2`, `remaining_quantity = 8`.
- Test D duplicate active tender invoice `ACC-SINV-2026-00019` was blocked with the expected duplicate-active-tender message.
  - Invoice stayed Draft.
  - No tender fulfillment rows were written.
  - Primary tender quantities remained `supplied_quantity = 2`, `remaining_quantity = 8`.
  - Duplicate tender `G3 Section 3 Duplicate Tender 2026-09-08` was closed after verification so it does not interfere with later tests.
- Section 3 passed on TEST.

### Pass conditions

- Correct tender price and available quantity allow submit.
- Wrong price blocks submit before tender quantity changes.
- Oversupply blocks submit before tender quantity changes.
- Duplicate active tender rows block submit.
- Submitted tender invoice writes `tender_fulfillments` audit rows.
- No manual transaction commit behavior is visible as partial tender updates after failed submit.

### Fail conditions

- Wrong price submits successfully.
- Oversupply submits successfully.
- Duplicate active tenders both get updated.
- Failed Sales Invoice submit still changes tender supplied quantity.
- No fulfillment audit row is written after valid submit.

---

## 4. Tender cancellation flow

**Covers fixes:** B-05

**Purpose:** Confirm cancelling a Sales Invoice reverses exactly the tender quantities recorded in `tender_fulfillments`.

### Roles/users

- `Ops - Accounting` or System Manager, depending on cancellation permissions.

### Required test data

Use the successfully submitted tender Sales Invoice from Section 3 Test A.

### Prepared TEST baseline — 2026-09-08

- Cancellation script `Sales-Invoice-on-cancel-tender-reversal.py` was patched on TEST to avoid `max(...)` and use a plain RestrictedPython-safe non-negative calculation.
- Use submitted Sales Invoice `ACC-SINV-2026-00016` from Section 3 Test A.
- Before cancellation:
  - Sales Invoice `docstatus = 1`, status `Unpaid`.
  - Sales Invoice has one `tender_fulfillments` row for Tender Agreement `G3 Section 3 Smoke Tender 2026-09-08`, item `3146-60450`, quantity `2`.
  - Tender Agreement item has `won_quantity = 10`, `supplied_quantity = 2`, `remaining_quantity = 8`.

### Steps

1. Record the Tender Agreement name.
2. Record the Tender Agreement Item `supplied_quantity` before cancellation.
3. Open the submitted Sales Invoice.
4. Confirm it has `tender_fulfillments` rows.
5. Cancel the Sales Invoice.
6. Reopen the Tender Agreement.
7. Confirm `supplied_quantity` decreased by exactly the quantity recorded in the Sales Invoice `tender_fulfillments` table.
8. Confirm `remaining_quantity = won_quantity - supplied_quantity`.
9. Confirm quantity does not become negative.

### TEST result — 2026-09-08

- Initial cancellation of `ACC-SINV-2026-00016` cancelled the invoice but did not reverse tender quantities because the Server Script event was configured as invalid `On Cancel` instead of Frappe v16 `After Cancel`.
- Fixed `Sales-Invoice-on-cancel-tender-reversal.py` on TEST:
  - event changed to `After Cancel`.
  - non-negative supplied quantity calculation changed to a plain RestrictedPython-safe `if` block.
- Prepared fresh submitted retest invoice `ACC-SINV-2026-00020` with one tender fulfillment row for Tender Agreement `G3 Section 3 Smoke Tender 2026-09-08`, item `3146-60450`, quantity `2`.
- Before retest cancellation, tender item values were `supplied_quantity = 4`, `remaining_quantity = 6`.
- User cancelled `ACC-SINV-2026-00020`.
- After cancellation:
  - Sales Invoice `ACC-SINV-2026-00020` has `docstatus = 2`, status `Cancelled`.
  - Tender item values are `supplied_quantity = 2`, `remaining_quantity = 8`.
  - Reversal matched exactly the recorded fulfillment quantity `2` and did not make supplied quantity negative.
- Section 4 passed on TEST using the retest invoice.

### Pass conditions

- Cancellation reverses exact fulfillment rows.
- Reversal does not depend on tender still being Active.
- Remaining quantity recalculates correctly.

### Fail conditions

- Cancellation does not reduce supplied quantity.
- Cancellation reverses the wrong tender/item.
- Cancellation reverses by current invoice items instead of recorded fulfillment rows.
- Supplied quantity becomes negative.

---

## 5. Tender status flow

**Covers fixes:** B-06

**Purpose:** Confirm manual `Closed` status is preserved and non-Closed statuses follow valid-date logic.

### Roles/users

- `Ops - Directors` or System Manager.

### Required test data

Create or use test Tender Agreements where it is safe to change dates/status.

### Test A — Closed stays Closed

1. Open a test Tender Agreement.
2. Set status to `Closed`.
3. Save.
4. Change another non-status field or save again.
5. Confirm status remains `Closed`.
6. Change valid dates so the tender would normally be Active or Expired.
7. Save again.
8. Confirm status still remains `Closed`.

### Test B — Draft/future/current/expired date behavior

1. Create or open a non-Closed Tender Agreement.
2. Set valid dates in the future.
3. Save.
4. Confirm status follows the expected future-date state.
5. Set valid dates covering today.
6. Save.
7. Confirm status becomes `Active`.
8. Set valid_to before today.
9. Save.
10. Confirm status becomes `Expired`.

### TEST result — 2026-09-08

- Test A tender `G3 Section 5 Closed Status Tender 2026-09-08` stayed `Closed` after save and date changes to `valid_from = 2026-09-01`, `valid_to = 2026-09-30`.
- Test B tender `G3 Section 5 Date Flow Tender 2026-09-08` followed date-driven status changes:
  - Future dates `valid_from = 2026-10-01`, `valid_to = 2026-12-17` kept status `Draft`.
  - Current active dates `valid_from = 2026-09-01`, `valid_to = 2026-12-31` set status `Active`.
  - Expired dates `valid_from = 2026-08-01`, `valid_to = 2026-08-31` set status `Expired`.
- Section 5 passed on TEST.

### Pass conditions

- `Closed` is never reopened by date logic.
- Non-Closed status follows valid_from/valid_to dates.
- Draft does not remain permanently Draft when date logic says Active/Expired.

### Fail conditions

- Saving a Closed tender changes it to Active/Expired/Draft.
- Current-date tender remains Draft incorrectly.
- Expired tender remains Active incorrectly.

---

## 6. Debt Closure Approval flow

**Covers fixes:** B-07, B-09

**Purpose:** Confirm Debt Closure Approval uses Task Access Policy and calculates profit across all linked invoices, writing per-Dispatch Case profit.

### Roles/users

- `Ops - Finance` for payment collection.
- `Ops - Directors` for closure approval.
- System Manager may be needed to inspect generated fields if role permissions block viewing.

### Required test data

Prepare or find:

1. A Debt Collection task with multiple `open_invoices` rows.
2. Each row should link a Sales Invoice.
3. Ideally, invoices should belong to different Dispatch Cases or at least clearly identifiable cases.
4. Items should have Standard Buying prices if profit calculation is expected to produce non-zero values.

### Steps

1. Complete payment collection so the Debt Collection task reaches full payment condition.
2. Confirm a Debt Closure Approval task is created or updated.
3. Confirm the approval task assignment comes from `Task Access Policy = Debt Closure Approval`.
4. Open **Task Access Policy** > `Debt Closure Approval`.
5. Confirm:
   - `default_team_user = directors.team@example.com`
   - allowed role includes `Ops - Directors`
6. Login as a user without `Ops - Directors`.
7. Attempt to complete the Debt Closure Approval task.
8. Confirm completion is blocked.
9. Login as `Ops - Directors`.
10. Review payment/invoice details.
11. Complete the Debt Closure Approval task.
12. Confirm total profit uses all linked Sales Invoices in `open_invoices`.
13. Open each linked Dispatch Case.
14. Confirm each Dispatch Case has its own profit value based on its own invoice(s), not only the first invoice/case.

### TEST result — 2026-09-08

- Initial approval task `TASK-2026-00542` verified Task Access Policy assignment and user acceptance/completion, but exposed that `custom_case_profit` did not persist when assigned directly in the After Save script.
- Patched `Task-after-save-debt-closure.py` on TEST to persist total profit with `frappe.db.set_value("Task", doc.name, "custom_case_profit", total_profit)`.
- Prepared retest task `TASK-2026-00546` with the same two linked invoices:
  - `ACC-SINV-2026-00008`, paid `4,680,000`.
  - `ACC-SINV-2026-00015`, paid `1,560,000`.
- User accepted and completed `TASK-2026-00546`.
- Verified result:
  - status `Completed`.
  - accepted/completed by `levonaghinyan77@gmail.com`.
  - `custom_case_profit = 6,239,443`.
  - independently recalculated expected profit was `6,239,443`.
- Section 6 policy/completion and multi-invoice profit persistence passed on TEST.
- Added missing `Debt Collection Invoice.dispatch_case` child-table link field on TEST to allow per-Dispatch Case profit coverage.
- Prepared full-coverage retest task `TASK-2026-00548` with Dispatch Case-linked open invoice rows:
  - `DC-2026-00150` linked to `ACC-SINV-2026-00008`.
  - `DC-2026-00151` linked to `ACC-SINV-2026-00015`.
- User accepted and completed `TASK-2026-00548`.
- Verified full result:
  - task status `Completed`.
  - `custom_case_profit = 6,239,443`.
  - `DC-2026-00150.profit = 4,680,000`.
  - `DC-2026-00151.profit = 1,559,443`.
- Section 6 fully passed on TEST.
- Completion showed the expected warning for missing Standard Buying prices on `BO.102.22.S`, `BO.102.24.S`, `BO.102.26.S`, and `BO.102.28.S`; the script still completed and calculated those item profits using buying rate `0` per current implementation.

### Pass conditions

- Approval assignment uses Task Access Policy, not hardcoded users.
- Only allowed role/user can complete approval.
- Profit calculation includes all linked invoices.
- Each linked Dispatch Case receives its own profit value.

### Fail conditions

- Approval goes to old hardcoded named users.
- Non-director can complete approval.
- Profit only considers the first invoice.
- All Dispatch Cases receive the same first-case profit incorrectly.

---

## 7. Scheduled Debt Alert flow

**Covers fixes:** B-08

**Purpose:** Confirm scheduled debt threshold monitoring creates Director `Debt Alert` tasks and does not create Finance `Debt Collection` tasks.

### Roles/users

- `Ops - Directors` for Debt Alert review.
- System Manager may be needed to trigger scheduler manually on TEST.

### Required test data

Prepare or find:

1. A Customer with `debt_threshold_amd` set.
2. Customer net receivable in GL Entry greater than the threshold.
3. `Task Access Policy = Debt Alert` exists.
4. `Debt Alert` exists as a `task_kind` option.

### Steps

1. Confirm test Customer's debt threshold.
2. Confirm Customer net receivable exceeds threshold.
3. Trigger the scheduled debt collection script on TEST or wait for scheduler run.
4. Search **Task** for `Debt Alert` tasks for that Customer.
5. Confirm the task subject is clearly `Debt Alert - {customer_name}`.
6. Confirm `task_kind = Debt Alert`.
7. Confirm assignment goes to the Directors policy/team user.
8. Confirm the task contains current debt and threshold information.
9. Search for scheduler-created `Debt Collection` tasks for the same Customer.
10. Confirm the scheduler did not create/update a Finance `Debt Collection` task for threshold alerting.
11. If a separate dispatch/payment Debt Collection task exists, confirm it remains the Finance payment workflow task and is not overwritten by the scheduler.

### TEST result — 2026-09-08

- Verified `Scheduled-debt-collection` is enabled as an Hourly Scheduler Event and uses `Debt Alert` rather than creating scheduler threshold `Debt Collection` tasks.
- Patched `Scheduled-debt-collection.py` on TEST so scheduler-created/updated Debt Alert tasks bypass the mandatory Task acceptance gate safely:
  - new alert tasks set debt/threshold/description before insert.
  - existing alert tasks update debt/threshold/description with `frappe.db.set_value`.
- Manually triggered the scheduler on TEST.
- Scheduler created Director Debt Alert tasks:
  - `TASK-2026-00549` for customer `D148 — Ահարոն — Հոկտեմբերյան ԲԿ - Inmed`, current debt `91,037,700`, threshold `5,000,000`.
  - `TASK-2026-00550` for customer `D146 — Խորեն Հովհաննիսյան — Օրթոպետիկ ԲԿ - Inmed`, current debt `88,522,200`, threshold `5,000,000`.
  - `TASK-2026-00551` for customer `D037 — Ջոն Կարապետյան — Գյումրի ԲԿ - Inmed`, current debt `10,140,000`, threshold `5,000,000`.
- User verified `TASK-2026-00549` in the UI:
  - status `Open`.
  - task kind `Debt Alert`.
  - Task Access Policy `Debt Alert`.
  - assigned to `directors.team@example.com`.
  - current debt and threshold visible.
  - description includes debt and threshold.
- Backend verified `TASK-2026-00549` has an open ToDo for `directors.team@example.com`.
- Backend and UI customer-filter check showed no scheduler-created Finance `Debt Collection` task for the same customer.
- Section 7 passed on TEST.

### Pass conditions

- Scheduler creates/updates `Debt Alert` tasks only.
- Debt Alert is assigned to Directors policy/team.
- Finance `Debt Collection` is not created by scheduler threshold logic.
- Existing Finance Debt Collection payment workflow is not overwritten.

### Fail conditions

- Scheduler creates Finance `Debt Collection` tasks.
- Debt Alert assigned to Finance or random/direct first user.
- Debt Alert lacks debt/threshold details.
- Scheduler overwrites Open Invoices/payment data on Debt Collection task.

---

## 8. Financial field permission flow

**Covers fixes:** B-10

**Purpose:** Confirm payment/profit fields are protected server-side, pricing remains available to Order Creating, and UI hiding matches permissions.

### Roles/users

Use at least these users or equivalent test users:

1. Non-financial operational user, e.g. Delivery Driver or Inventory.
2. `Ops - Order Creating` user.
3. `Ops - Finance` or `Ops - Accounting` user.
4. `Ops - Directors` or System Manager.

### Fields under test

Payment/profit fields on Dispatch Case:

- `sales_invoice`
- `prepaid_amount`
- `prepaid_payment_entry`
- `total_invoice_amount`
- `total_paid_amount`
- `outstanding_amount`
- `profit`
- `advance_payments`

Pricing fields on Dispatch Case Item:

- `unit_price`
- `discount_pct`

### Test A — non-financial user

1. Login as a non-financial operational user.
2. Try to open a Dispatch Case that the user can access.
3. Confirm payment/profit fields are not visible in the UI.
4. Confirm pricing fields are hidden if this role is not `Ops - Order Creating` or financial.
5. If API testing is available, verify the same user cannot retrieve protected permlevel fields server-side.

### Test B — Order Creating user

1. Login as `Ops - Order Creating`.
2. Create or open an editable Dispatch Case in the order creation stage.
3. Confirm `unit_price` is visible/editable where order creation requires it.
4. Confirm `discount_pct` is visible/editable where order creation requires it.
5. Confirm payment/profit fields are not visible:
   - `prepaid_amount`
   - `outstanding_amount`
   - `profit`
   - `advance_payments`
6. Save a normal order creation case to confirm the role can still do its job.

### Test C — Finance/Accounting user

1. Login as `Ops - Finance` or `Ops - Accounting`.
2. Open a Dispatch Case with payment/profit fields populated.
3. Confirm payment/profit fields are visible.
4. Confirm `advance_payments` child table is visible.
5. Confirm pricing fields are visible.

### Test D — Director/System Manager

1. Login as `Ops - Directors` or System Manager.
2. Open the same Dispatch Case.
3. Confirm payment/profit fields are visible.
4. Confirm pricing fields are visible.

### TEST result — 2026-09-08

- Used Dispatch Case `DC-2026-00144` with populated invoice/payment fields and case item rows.
- Backend verified field permlevels and role access:
  - financial Dispatch Case fields are permlevel `1` and readable/writable by `Ops - Accounting`, `Ops - Finance`, `Ops - Directors`, and `System Manager`.
  - `Dispatch Case Item.unit_price` and `Dispatch Case Item.discount_pct` are permlevel `2` and readable/writable by `Ops - Order Creating`, accounting/finance/directors, and System Manager.
  - `driver.01@example.com` has no financial/pricing permlevel access.
  - `artursemerjyan91@gmail.com` has pricing access through `Ops - Order Creating` and no financial access.
- User UI-tested real users:
  - `driver.01@example.com`: payment/profit fields, Advance Payments, Unit Price, and Discount % hidden.
  - `artursemerjyan91@gmail.com`: Unit Price and Discount % visible in Case Items row detail; payment/profit fields hidden.
  - Finance/Accounting user: Invoice and Payment section, Sales Invoice, Profit, Prepaid Amount, Prepaid Payment Entry, Advance Payments, Invoice Amount, Total Paid, Outstanding, Unit Price, and Discount % visible.
  - Directors user: Invoice and Payment section, Sales Invoice, Profit, Prepaid Amount, Prepaid Payment Entry, Advance Payments, Invoice Amount, Total Paid, Outstanding, Unit Price, and Discount % visible.
- Live client script `Dispatch Case-Price Visibility` verified enabled on TEST.
- Section 8 fully passed on TEST.

### Pass conditions

- Non-financial roles cannot see payment/profit fields.
- `Ops - Order Creating` can still enter `unit_price` and `discount_pct`.
- `Ops - Order Creating` cannot see payment/profit fields.
- Finance/Accounting/Directors/System Manager can see protected financial fields.
- Server-side permissions match UI behavior.

### Fail conditions

- Non-financial user can retrieve payment/profit fields via UI or API.
- Order Creating cannot enter price/discount.
- Finance/Accounting cannot see advance/payment/profit details.
- UI hides fields but API still exposes them to unauthorized users.

---

## 9. Final sign-off checklist

Mark each section only after the functional steps pass on TEST.

| Section | Area | Fixes covered | Result | Notes/document names |
|---|---|---|---|---|
| 1 | Debt Collection payment flow | B-01, B-11, B-12 | Pass | Section 1 passed on TEST after RestrictedPython/payment-history fixes. |
| 2 | Customer advance payment flow | B-03, B-12 | Pass | Section 2 passed on TEST with cash and bank-transfer advance rows. |
| 3 | Tender submit flow | B-04, B-05, B-13, tender price validation | Pass | Section 3 passed on TEST with valid submit and blocked invalid cases. |
| 4 | Tender cancellation flow | B-05 | Pass | Section 4 passed on TEST after event correction to After Cancel. |
| 5 | Tender status flow | B-06 | Pass | Section 5 passed on TEST for Draft/Active/Expired/Closed behavior. |
| 6 | Debt Closure Approval flow | B-07, B-09 | Pass | Section 6 fully passed on TEST with total and per-Dispatch Case profit. |
| 7 | Scheduled Debt Alert flow | B-08 | Pass | Section 7 passed on TEST with Debt Alert-only scheduler behavior. |
| 8 | Financial field permission flow | B-10 | Pass | Section 8 fully passed on TEST with backend and real-user UI checks. |

Group 3 can be considered ready for prod promotion only after all eight sections pass or any exceptions are explicitly accepted by the business owner.
