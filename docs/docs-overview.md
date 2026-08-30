# ERPNext Documentation Set — Overview (Medical Supplier, Armenia)

## 1) Purpose
This document defines the full documentation set we will produce for implementing ERPNext for your medical supplier business in Armenia.

Scope includes ERPNext functional setup and business workflows. Infrastructure topics (domain/SSL/backups/email/VPS) are excluded.

## 2) Audience
- Primary reader: a new worker who is sharp but new to ERPNext
- Secondary readers: you / director team for approvals and review

## 2.1) Working-condition status
**Last reviewed:** 2026-06-01

These statuses describe whether the matching ERPNext area is already in working condition, not only whether the document text is written.

### Working or mostly working in ERPNext
| File | Working status |
|---|---|
| `03-roles-permissions-responsibilities.md` | ✅ FULLY READY for current go-live step: Role Permission Manager completed manually; every operational role has at least one real user; dangerous roles only on developer account; Employee records deferred; example users to revisit before final go-live |
| `03-roles-permissions-responsibilities-implementation.md` | ✅ FULLY READY for current go-live step: Role Permission Manager completed manually; every operational role has at least one real user; dangerous roles only on developer account; Employee records deferred; example users to revisit before final go-live |
| `04-customers-and-doctors.md` | ✅ FULLY READY for current go-live step: real customers exist; no test/fake customer data found; debt thresholds are filled, with exact values to be adjusted after launch if needed; customer names are recognizable |
| `04-customers-and-doctors-implementation.md` | ✅ FULLY READY for current go-live step: real customers exist; no test/fake customer data found; debt thresholds are filled, with exact values to be adjusted after launch if needed; customer names are recognizable |
| `05-warehouses-and-stock-rules.md` | ✅ FULLY READY for current go-live step: core warehouses exist; client/doctor warehouses are under `Clients - Inmed`; no obvious wrong structure found; team rule accepted that stock should not bypass Dispatch Case/in-transit flow |
| `05-warehouses-and-stock-rules-implementation.md` | ✅ FULLY READY for current go-live step: core warehouses exist; client/doctor warehouses are under `Clients - Inmed`; no obvious wrong structure found; team rule accepted that stock should not bypass Dispatch Case/in-transit flow |
| `06-items-variants-uoms.md` | ✅ FULLY READY: Item tracking flags applied and verified for 3318 reviewed rows |
| `06-items-variants-uoms-implementation.md` | ✅ FULLY READY: Item tracking flags applied and verified for 3318 reviewed rows |
| `07-suppliers-and-procurement-basic.md` | ✅ FULLY READY for current go-live step: supplier master list completed; purchasing roles manually confirmed; no broken draft POs; USD→AMD exchange record created for testing; draft PO save works; director approval task blocks submit until approved; approved PO submit tested successfully |
| `07-suppliers-and-procurement-basic-implementation.md` | ✅ FULLY READY for current go-live step: supplier master list completed; purchasing roles manually confirmed; no broken draft POs; USD→AMD exchange record created for testing; draft PO save works; director approval task blocks submit until approved; approved PO submit tested successfully |
| `08-reorder-and-ordering-by-supplier.md` | ✅ SOFTWARE READY for current go-live step: purchasing roles confirmed; reorder fields exist; `Stock Projected Qty`, `Item Shortage Report`, and `RPT — Purchasing — Norm and Reorder` open successfully; business reorder levels/quantities intentionally deferred for testing/real stock decisions |
| `08-reorder-and-ordering-by-supplier-implementation.md` | ✅ SOFTWARE READY for current go-live step: purchasing roles confirmed; reorder fields exist; `Stock Projected Qty`, `Item Shortage Report`, and `RPT — Purchasing — Norm and Reorder` open successfully; business reorder levels/quantities intentionally deferred for testing/real stock decisions |
| `10-task-system-foundations.md` | ✅ READY for launch foundation: Task list/form open; Task Access Policy records exist; Purchase Approval task and PO approval writeback tested; minor task cleanup/usability refinements can be handled during testing month |
| `10-task-system-foundations-implementation.md` | ✅ READY for launch foundation: Task list/form open; Task Access Policy records exist; Purchase Approval task and PO approval writeback tested; minor task cleanup/usability refinements can be handled during testing month |
| `14-go-live-checklist.md` | ✅ Checklist usable; final go-live checks still must be run |
| `go-live-action-plan.md` | ✅ Current local launch checklist; implementation work is complete for Docs 15/16/17, remaining work is smoke testing and master data |

### Deployed / prepared but still needs live smoke testing
| File | Working status |
|---|---|
| `02-navigation-and-naming.md` | 🟡 Naming rules documented; item group/naming cleanup still open |
| `10.1-directors-task-dashboard.md` | 🟡 Optional wallboard/dashboard area; not required for first transaction |
| `10.1-directors-task-dashboard-implementation.md` | 🟡 Optional wallboard/dashboard area; not required for first transaction |
| `13-reporting-pack.md` | 🟡 Reports/workspace deployed; report outputs still need validation with real/test transactions |
| `13-reporting-pack-implementation.md` | 🟡 Reports/workspace deployed; report outputs still need validation with real/test transactions |
| `15-reporting-requirements-review.md` | 🟡 Software deployed; report value quality depends on Standard Buying prices and real/test transactions |
| `15a-reporting-requirements-implementation.md` | 🟡 26/26 reports/functions/workspaces deployed or existing; remaining work is smoke testing and master-data-dependent value validation |
| `16-unified-dispatch-flow.md` | 🟡 Dispatch Case flow deployed; `unit_price` optional; end-to-end no-return and return-expected smoke tests still required |
| `16a-unified-dispatch-flow-implementation.md` | 🟡 Dispatch Case implementation deployed; `unit_price` optional; end-to-end no-return and return-expected smoke tests still required |
| `16b-unified-dispatch-flow-gap-analysis.md` | 🟡 No core implementation gap remains; `Dispatch - Task Queues` workspace deployed; business workflow still needs smoke test |
| `17-purchase-cost-and-valuation.md` | 🟡 Costing support deployed; Standard Buying prices, HS codes/import tax rates still incomplete |
| `17a-purchase-cost-and-valuation-implementation.md` | 🟡 Costing support deployed; Standard Buying prices, HS codes/import tax rates still incomplete; LCV flow needs smoke test |
| `18-photo-system.md` | Photo system requirements - authoritative reference; deployed logging on test; corrections to other docs applied |
| `ERPNext Barcode/FIXES_DOCUMENTATION.md` | 🟡 Barcode logic prepared; live Purchase Receipt deployment/smoke test still required |
| `ERPNext Barcode/IMPLEMENTATION_READY.md` | 🟡 Barcode implementation-ready; live deployment/smoke test still required |

### Superseded / historical reference only
| File | Working status |
|---|---|
| `09-standard-selling-flow.md` | ⚪ Superseded by Doc 16; do not use as current working flow |
| `09-standard-selling-flow-implementation.md` | ⚪ Superseded by Doc 16A; do not use as current working flow |
| `11-surgery-set-model.md` | ⚪ Superseded by Doc 16; retained only for historical/template context |
| `11-surgery-set-implementation.md` | ⚪ Superseded by Doc 16A; retained only for historical/template context |
| `12-surgery-set-operational-workflow.md` | ⚪ Superseded by Doc 16; do not use as current working flow |
| `12-surgery-set-operational-workflow-implementation.md` | ⚪ Superseded by Doc 16A; do not use as current working flow |

### Reference / not a working-process document
| File | Working status |
|---|---|
| `implementation-questions.md` | 🟡 Reference / open inputs list |
| `ai-agent-api-access-guide.md` | 🟡 Reference |
| `docs-overview.md` | 🟡 Index / status tracker |
| `infrastructure-test-vs-prod-environments.md` | 🟡 Infra reference (excluded from functional scope, see §1); test instance live at test.erpnext.am since 2026-07-15 |

## 3) Document sequence (recommended)
### 01 — Requirements
**File**: `requirements.md`
- **Purpose**: Single source of truth for scope, decisions, and acceptance criteria.
- **Status**: Created and updated.

### D0 — Directors Design Pack (Presentation)
**File**: `directors-design-pack.md`
- **Purpose**: Directors-facing summary of requirements → solutions/approaches/features, with governance, reporting visibility, go-live readiness, and a decision/Q&A appendix.

### D0B — Directors Business Brief (Plain Language)
**File**: `directors-business.md`
- **Purpose**: Directors-facing brief in business language with minimal system terminology: goals, flows (Level 1), key features/controls, reports, and open questions.

### D0B-RU — Бизнес-брифинг для директоров (на русском языке)
**File**: `directors-business-ru.md`
- **Purpose**: Russian translation of the Directors Business Brief, including English terms in parentheses for clarity.

### Q0 — Implementation Questions (Data Required)
**File**: `implementation-questions.md`
- **Purpose**: A running list of concrete data inputs required to fully implement the solution (users/roles, task visibility policies, master lists, etc.).

### 02 — Doc Set Navigation & Naming Conventions
**File**: `02-navigation-and-naming.md`
- **Purpose**: How to name Companies, Warehouses, Items, Customers (Clients), Set Types, numbering series; how to keep master data clean.
- **Outputs**:
  - Naming templates (e.g., client location warehouse naming)
  - Required fields checklist

### 03 — Roles, Permissions, and Team Responsibilities
**File**: `03-roles-permissions-responsibilities.md`
- **Purpose**: Define roles for:
  - Order Creation team
  - Preparing team
  - Delivery team
  - Accounting team
  - Returns team
  - Purchasing team
  - Director approval team
  - “Usage Info” team/role
- **Outputs**:
  - Responsibility matrix
  - Permission rules to prevent unauthorized cancellations/edits (lightweight)

### 03A — Roles, Permissions, and Team Responsibilities (Implementation)
**File**: `03-roles-permissions-responsibilities-implementation.md`
- **Purpose**: Step-by-step ERPNext setup for roles, role permission rules, Task Access Policy visibility, and smoke tests.

### 04 — Master Data: Customers (Clients)
**File**: `04-customers-and-doctors.md`
- **Purpose**: Create clients as Customers (mostly doctors, sometimes hospitals) and capture optional hospital/doctor context on transactions without a separate Doctor master.
- **Outputs**:
  - Customer creation checklist
  - How to capture hospital + doctor context on orders/cases for reporting

### 04A — Customers (Clients) (Implementation)
**File**: `04-customers-and-doctors-implementation.md`
- **Purpose**: Step-by-step ERPNext setup for client Customers (code + debt threshold) and optional hospital/doctor context fields on selling/operations documents.

### 05 — Inventory Foundation: Warehouses, Stock Rules
**File**: `05-warehouses-and-stock-rules.md`
- **Purpose**: Implement client-level stock visibility.
- **Key decisions embedded**:
  - One warehouse per doctor-hospital-branch client location group under `Clients - Inmed`
  - Staging warehouses for logistics:
    - `Delivery In-Transit - Inmed`
    - `Return Pickup In-Transit - Inmed`
  - Delivery person “has what” is tracked via assignment records and derived in reporting (no per-driver warehouses)
- **Outputs**:
  - Warehouse tree
  - Stock movement rules (which documents move stock)
  - Returns destination policy (`Returns - Inmed` vs direct to main)

### 05A — Warehouses, Stock Rules (Implementation)
**File**: `05-warehouses-and-stock-rules-implementation.md`
- **Purpose**: Step-by-step ERPNext setup for the Doc 05 warehouse tree, stock settings guardrails, and validation.

### 06 — Item Catalog and Variants
**File**: `06-items-variants-uoms.md`
- **Purpose**: Build a scalable item catalog including variants (sizes/versions).
- **Outputs**:
  - Item Group structure
  - Variant strategy
  - Required fields

### 06A — Item Catalog and Variants (Implementation)
**File**: `06-items-variants-uoms-implementation.md`
- **Purpose**: Step-by-step ERPNext setup for Item Groups, UOMs, variants (Item Attributes/Templates), tracking flags (batch/expiry/serial), and validation.

### 07 — Suppliers and Procurement (Basic P2P)
**File**: `07-suppliers-and-procurement-basic.md`
- **Purpose**: Suppliers + Purchase Order → Receipt → Purchase Invoice.
- **Outputs**:
  - Supplier setup
  - Purchase flow
  - Director approval requirement (PO approval)

### 07A — Suppliers and Procurement (Basic P2P) (Implementation)
**File**: `07-suppliers-and-procurement-basic-implementation.md`
- **Purpose**: Step-by-step ERPNext setup for suppliers, P2P flow, and enforcing director PO approval.

### 07.1 — Procurement Shipment/Import Status Workflow
**Planned file**: `07.1-procurement-shipment-import-workflow.md`
- **Purpose**: Track international procurement through statuses/tasks (need to order → ordering → ordered → shipped → import → accepted to warehouse).
- **Outputs**:
  - Status definitions
  - Ownership per status
  - Required fields/attachments per stage (if any)

### 08 — Reorder System (Low Stock → PO per Supplier)
**File**: `08-reorder-and-ordering-by-supplier.md`
- **Purpose**: Configure and operationalize the “always-available reorder list”.
- **Key decisions embedded**:
  - No fixed ordering cycle yet
  - One item → one supplier
  - Reorder list must be filterable/groupable by supplier
- **Outputs**:
  - Reorder thresholds rules
  - Daily/weekly operating procedure for purchasing team
  - PO approval workflow (director)

### 08A — Reorder System (Implementation)
**File**: `08-reorder-and-ordering-by-supplier-implementation.md`
- **Purpose**: Step-by-step ERPNext setup for item reorder thresholds (including variants), reorder visibility, and governance controls.

### 09 — Selling: Standard Orders (No Return Expected) *(Superseded by Doc 16)*
**File**: `09-standard-selling-flow.md`
> **⚠️ This document describes the old Sales Order–based flow. It is superseded by Doc 16 — Unified Dispatch Flow, which replaces both standard sales and surgery cases with the Dispatch Case DocType. Retained for historical reference only.**
- **Purpose**: Client orders items; you deliver; you invoice; they pay later.
- **Outputs**:
  - Sales order capture rules
  - Delivery process
  - Invoicing and receivables basics
  - Client debt thresholds + automated director Debt Collection task rule
  - Optional hospital/doctor context capture on Sales Order and Sales Invoice
  - Discount entry + approval points (order team applies; director approves)

### 09A — Selling: Standard Orders (Implementation) *(Superseded by Doc 16A)*
**File**: `09-standard-selling-flow-implementation.md`
> **⚠️ Superseded by Doc 16A — Unified Dispatch Flow (Implementation). Retained for historical reference only.**
- **Purpose**: Step-by-step ERPNext setup for standard sales flow, dispatch staging via `Delivery In-Transit - Inmed`, discount approval gate, prepaid gate, debt escalation tasks, and payment distribution tasks.

### 09.1 — Discounts and Approvals
**Planned file**: `09.1-discounts-and-approvals.md`
- **Purpose**: Define how discounts are applied and approved.
- **Outputs**:
  - Who can apply discounts
  - Director approval rules
  - Auditability expectations

### 10 — Task System Foundations
**File**: `10-task-system-foundations.md`
- **Purpose**: Define how the company runs operations through tasks (owners, statuses, stage gates).
- **Outputs**:
  - Task states and assignment rules
  - SLA expectations (optional)
  - Mandatory attachment rule for return pickup tasks (photo)

### 10A — Task System Foundations (Implementation)
**File**: `10-task-system-foundations-implementation.md`
- **Purpose**: Step-by-step ERPNext setup for the Task system (Task Kind field, standard link fields, driver permissions, mandatory pickup photo enforcement, and stage-gate patterns).
- **Outputs**:
  - Custom fields on Task
  - Permission rules (drivers only see/complete tasks)
  - Server-side enforcement for pickup photo + completed timestamp
  - Reusable stage-gate patterns

### 10.1 — Directors Task Dashboard (TV / Wallboard)
**File**: `10.1-directors-task-dashboard.md`
- **Purpose**: Define how directors can view all operational tasks on a TV/dashboard.
- **Outputs**:
  - Option A: Saved Task list view (grouped by Assigned To) for a wallboard
  - Option B: Directors Workspace page with links/cards for key task queues

### 10.1A — Directors Task Dashboard (Implementation)
**File**: `10.1-directors-task-dashboard-implementation.md`
- **Purpose**: Step-by-step ERPNext setup for the directors TV wallboard (TV user, permissions, Task Access Policy visibility, saved Task list views, Workspace shortcuts, kiosk setup).

### 11 — Surgery Set Model (How sets are represented) *(Superseded by Doc 16)*
**File**: `11-surgery-set-model.md`
> **⚠️ The Surgery Set DocType and its operational workflow are superseded by Doc 16 — Unified Dispatch Flow, which uses the Dispatch Case DocType with `return_expected = Yes` for cases where items come back. The `Collection Set` item template concept is retained as a template source for Dispatch Cases. Retained for historical reference only.**
- **Purpose**: Define set templates + inventory representation at client locations.
- **Key decisions embedded**:
  - Custom DocType `Collection Set`
  - Client-level warehouses for "items at client location”

### 12 — Surgery Set Operational Workflow (End-to-End) *(Superseded by Doc 16)*
**File**: `12-surgery-set-operational-workflow.md`
> **⚠️ This document describes the old Surgery Case workflow. It is superseded by Doc 16 — Unified Dispatch Flow (Dispatch Case with `return_expected = Yes`). Retained for historical reference only.**
- **Purpose**: Step-by-step procedure from order → prepare → dispatch → wait usage info → pickup returns (photo) → returns processing → invoice used items.
- **Outputs**:
  - Document sequence in ERPNext
  - Stock movement rules per step
  - Task creation/ownership rules per step
  - Reconciliation rules: Delivered = Used + Returned

### 12A — Surgery Set Operational Workflow (Implementation) *(Superseded by Doc 16A)*
**File**: `12-surgery-set-operational-workflow-implementation.md`
> **⚠️ Superseded by Doc 16A — Unified Dispatch Flow (Implementation). Retained for historical reference only.**
- **Purpose**: Step-by-step ERPNext setup for implementing Doc 12 (custom DocTypes/fields, workflows, permissions, scripts/automation, and validation gates).

### 13 — Reporting Pack
**File**: `13-reporting-pack.md`
- **Purpose**: Provide the “how to see everything” views:
  - Items currently at each client location
  - Items currently with each delivery person (outgoing in-transit and return pickup in-transit)
  - Aging of open Dispatch Cases (by status / stuck detection)
  - Unpaid invoices
  - Clients exceeding their debt threshold
  - Open Debt Collection tasks (per client) with current debt
  - Sales history per client (with optional hospital/doctor context when recorded)
  - Low stock list by supplier

### 14 — Go-Live Readiness Checklist (Functional)
**File**: `14-go-live-checklist.md`
- **Purpose**: Ensure master data and flows are ready before entering real operations.
- **Outputs**:
  - Minimum viable setup checklist
  - Test scenarios checklist

### 15 — Reporting Requirements Review
**File**: `15-reporting-requirements-review.md`
- **Purpose**: Consolidates the 20 requested reports/functions into 26 implementation-ready ERPNext specifications. Documents all confirmed decisions (financial definitions, access control, debt rules, norm calculation). Cross-references Doc 13/13A for already-built reports. Proposes 4 phased implementation phases.
- **Status**: Software deployed through Doc 15E; remaining validation depends on smoke tests, Standard Buying prices, and real/test transaction data.

### 15A — Reporting Requirements: Implementation Status and Build Plan
**File**: `15a-reporting-requirements-implementation.md`
- **Purpose**: Current implementation status for all 26 Doc 15 reports/functions/workspaces, including Doc 15A–15E deployment scripts and remaining operational validation.
- **Snapshot date**: 2026-06-01
- **Key findings**: All 26 items are deployed or existing. Doc 15E added the remaining item reports, return/refund queue, norm notification scheduler, and clean workspaces. Remaining work is smoke testing and master-data-dependent report validation.

### 16 — Unified Dispatch Flow *(Current — Replaces Docs 09, 11, 12)*
**File**: `16-unified-dispatch-flow.md`
- **Purpose**: Single unified flow for all client deliveries. Replaces the separate standard sale (Doc 09) and surgery case (Doc 12) flows with a single `Dispatch Case` DocType. The `return_expected` flag on the case selects the path: **No** = stock flows all the way through to consumption; **Yes** = stock is delivered to client warehouse, returned after use, inspected, and invoiced for used quantities only.
- **Key concepts**:
  - Dispatch Case DocType with full automated task chain
  - 14 case states from Draft → Closed
  - Stock entries auto-submitted at each transition
  - Roles: `Ops - Order Creating`, `Ops - Order Accepting`, `Ops - Inventory`, `Delivery Driver`, `Ops - Returns`, `Ops - Accounting`, `Ops - Finance`
  - Debt Collection and Distribute Payment tasks integrated

### 16A — Unified Dispatch Flow (Implementation)
**File**: `16a-unified-dispatch-flow-implementation.md`
- **Purpose**: Step-by-step ERPNext setup for Dispatch Case DocType, child tables, custom fields, server scripts, client scripts, roles, and Task Access Policies.
- **Current status**: Deployed; `Dispatch Case Item.unit_price` is optional; workspace/task shortcuts are available through `Dispatch - Task Queues`.

### 16B — Unified Dispatch Flow Gap Analysis
**File**: `16b-unified-dispatch-flow-gap-analysis.md`
- **Purpose**: Deployment gap analysis — what was needed vs. what existed, deployment progress, and final state after `doc16a-deploy.ps1`.
- **Current status**: No core implementation gap remains; end-to-end smoke tests are still required before final sign-off.

---

### 17 — Purchase Flow with Costing and Valuation
**File**: `17-purchase-cost-and-valuation.md`
- **Prod status (2026-06-01):** FIFO valuation ✅, PR/PO scripts ✅, `hs_code`/`import_tax_rate` fields ✅, LCV client script ✅ | Standard Buying prices / HS codes / import tax rates still need master-data population

### 17A — Purchase Flow with Costing and Valuation (Implementation)
**File**: `17a-purchase-cost-and-valuation-implementation.md`
- **Purpose**: Step-by-step ERPNext setup — Item hs_code/import_tax_rate fields, LCV import-duty pre-fill client script, operating procedures for PR/LCV/PI, deploy script skeleton, and smoke tests. Full prod state analysis included.
- **Current status**: Technical deployment complete; purchase-costing smoke test and master data remain.

### 18 — Photo System
**File**: `18-photo-system.md`
- **Purpose**: Complete photo requirements for the Task system — which task kinds require/allow/prohibit photos, completion gates, propagation rules, field visibility, permission model, upload limits, and observability.
- **Current status**: Authoritative reference. Supersedes photo sections in Docs 10/12/16 where they conflict.

---

## 4) Future phase documents (explicitly deferred)
These docs are planned later (not required for initial go-live):

## 5) Status / workflow rule
We will draft and modify individual process docs (Doc 11, Doc 12, etc.) only when you explicitly approve.
