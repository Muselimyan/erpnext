# ERPNext Playwright Audit Gaps

## Purpose

This register tracks known skipped, audit-only, environment-dependent, or fixture-dependent Playwright checks.

The test section must not be called finished while any unresolved entry remains here. Use current baseline or stabilized baseline instead.

## Current status

Last verified against `https://test.erpnext.am` on 2026-09-16:

| Project/check | Result |
|---|---|
| `npx tsc --noEmit` | passed |
| `api` | 27 passed |
| `desktop` + `mobile` | 284 passed, 5 skipped |
| `e2e` | 2 passed |
| `api-audit` | 270 passed, 139 skipped |
| `e2e-audit` | 1 passed, 3 skipped |

The Playwright suite has a stabilized current baseline, but it is not finished by the project quality standard.

## Gap categories

| Category | Meaning | Blocks finished? |
|---|---|---|
| Audit-only spec | Test is tagged `@audit` and excluded from blocking stable projects | Yes |
| Non-enforced gate | Test expects a business/security validation not consistently enforced by the current test environment | Yes |
| Return workflow gap | Return-expected flow behavior is incomplete or differs from the desired contract | Yes |
| Metadata exposure gap | Metadata fields are not consistently exposed by the current `getdoctype` API response | Yes |
| Missing deployed config | Expected report, workspace, script, or fixture is absent in the current environment | Yes |
| Fixture/data dependency | Test depends on mutable existing data or a fixture that may not exist | Yes |

## Current inventory

### Stable-project conditional skips

| Area | File | Reason | Required resolution |
|---|---|---|---|
| Discount/Pack task creation | `tests/e2e/tests/api/discount-and-gates.spec.ts` | Pack task may not be created by current server scripts | Make setup deterministic or move/keep as documented audit gap |
| Dispatch lifecycle Pack task creation | `tests/e2e/tests/api/dispatch-lifecycle.spec.ts` | Pack task may not be created by current server scripts | Make setup deterministic or move/keep as documented audit gap |

### Audit-only API specs

| Area | Representative files | Current status | Required resolution |
|---|---|---|---|
| Data quality/master data | `tests/e2e/tests/api/data-quality-master-data.spec.ts` | Audit-only, includes deployed report/data assumptions | Confirm required reports/data or keep as audit backlog |
| Dispatch edge/gate behavior | `tests/e2e/tests/api/dispatch-edge-cases.spec.ts`, `tests/e2e/tests/api/dispatch-workflow-gate-depth.spec.ts` | Audit-only, includes non-enforced gates | Decide desired ERPNext behavior, then enforce or adjust tests |
| Item/stock governance | `tests/e2e/tests/api/item-stock-governance.spec.ts` | Audit-only, includes metadata/report/script assumptions | Confirm deployed governance model and metadata access |
| Master data/config | `tests/e2e/tests/api/master-data-config.spec.ts`, `tests/e2e/tests/api/preflight.spec.ts` | Audit-only, includes metadata/report/workspace assumptions | Decide required deployed config for go-live baseline |
| Packing/Product Work Area | `tests/e2e/tests/api/packing-product-work-area.spec.ts` | Audit-only, includes unstable mutation/gate assertions | Stabilize packing APIs or keep desired contracts documented |
| Payments/debt/tender | `tests/e2e/tests/api/payment-debt-workflow.spec.ts`, `tests/e2e/tests/api/payments-debt-tender.spec.ts` | Audit-only, includes non-enforced payment/debt gates | Decide desired financial validation gates and implement/test later |
| Permission/security | `tests/e2e/tests/api/permission-negative-matrix.spec.ts` | Audit-only, includes non-enforced lock/ownership gates | Decide security contract and enforce before promoting to stable |
| Purchase approval/reorder | `tests/e2e/tests/api/purchase-approval-workflow.spec.ts`, `tests/e2e/tests/api/purchasing-reorder-supplier.spec.ts` | Audit-only, includes purchase approval and supplier/reorder assumptions | Confirm purchase workflow priority and current deployed behavior |
| Reports/workspaces | `tests/e2e/tests/api/report-content-filters.spec.ts`, `tests/e2e/tests/api/report-metadata-depth.spec.ts`, `tests/e2e/tests/api/reports-workspaces.spec.ts` | Audit-only report metadata/content checks | Confirm official report/workspace list and required role access |
| Returns workflow | `tests/e2e/tests/api/returns-workflow.spec.ts` | Audit-only, Return Call/return quantity flow not fully stable | Define current vs desired return path and stabilize E2E fixture creation |
| Script safety/ownership | `tests/e2e/tests/api/script-static-safety.spec.ts`, `tests/e2e/tests/api/script-ownership-depth.spec.ts` | Audit-only script contract checks | Review expected markers and ownership boundaries |
| Surgical kit/item selection | `tests/e2e/tests/api/surgical-kit-template.spec.ts` | Audit-only, includes metadata/UI item-selection assumptions | Confirm template model and deployed selector behavior |
| Task policy/security | `tests/e2e/tests/api/task-policy-matrix.spec.ts`, `tests/e2e/tests/api/task-policy-depth-matrix.spec.ts`, `tests/e2e/tests/api/task-lock-security-depth.spec.ts` | Audit-only policy/lock/security checks | Confirm policy records and lock enforcement expectations |

### Audit-only E2E specs

| Area | File | Current status | Required resolution |
|---|---|---|---|
| Return-expected happy path | `tests/e2e/tests/e2e/return-expected-happy-path.spec.ts` | Audit-only; current environment does not create Return Call directly after return-expected delivery and lacks stable accepted return task fixture | Define actual desired return path, create deterministic setup, then promote stable parts |

### Smoke/UI conditional skips

| Area | File | Reason | Required resolution |
|---|---|---|---|
| Master form fixtures | `tests/e2e/tests/smoke/master-form-load-ui.spec.ts` | Fixture document may not be present in current test data | Create deterministic read-only fixture discovery/setup |
| Mobile back button | `tests/e2e/tests/smoke/mobile-layout-and-buttons.spec.ts` | Optional mobile back button may not exist in current deployed UI | Decide whether the button is required or optional |
| Pack task fixture | `tests/e2e/tests/smoke/mobile-layout-and-buttons.spec.ts` | Pack task fixture may not be created in current server state | Create deterministic Pack task fixture setup |

## Next actions

1. Re-run stable projects and confirm the current baseline.
2. Run audit projects separately and capture actual failures/skips.
3. Classify each audit gap as current desired behavior, future desired behavior, fixture issue, metadata access issue, or real ERPNext issue.
4. Remove stable-project conditional skips by making setup deterministic or moving those checks to audit.
5. Promote only reliable current behavior checks from audit into stable projects.
6. Keep this register updated whenever a skip, audit tag, or known test limitation is added/removed.
