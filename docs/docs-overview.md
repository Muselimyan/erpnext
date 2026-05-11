# ERPNext Documentation Set — Overview (Medical Supplier, Armenia)

## 1) Purpose
This document defines the full documentation set we will produce for implementing ERPNext for your medical supplier business in Armenia.

Scope includes ERPNext functional setup and business workflows. Infrastructure topics (domain/SSL/backups/email/VPS) are excluded.

## 2) Audience
- Primary reader: a new worker who is sharp but new to ERPNext
- Secondary readers: you / director team for approvals and review

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
  - One warehouse per doctor-hospital-branch client location group under `Clients - WH`
  - Staging warehouses for logistics:
    - `Delivery In-Transit - WH`
    - `Return Pickup In-Transit - WH`
  - Delivery person “has what” is tracked via assignment records and derived in reporting (no per-driver warehouses)
- **Outputs**:
  - Warehouse tree
  - Stock movement rules (which documents move stock)
  - Returns destination policy (`Returns - WH` vs direct to main)

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
- **Purpose**: Step-by-step ERPNext setup for standard sales flow, dispatch staging via `Delivery In-Transit - WH`, discount approval gate, prepaid gate, debt escalation tasks, and payment distribution tasks.

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
> **⚠️ The Surgery Set DocType and its operational workflow are superseded by Doc 16 — Unified Dispatch Flow, which uses the Dispatch Case DocType with `return_expected = Yes` for cases where items come back. The `Surgery Set Type` item template concept is retained as a template source for Dispatch Cases. Retained for historical reference only.**
- **Purpose**: Define set templates + inventory representation at client locations.
- **Key decisions embedded**:
  - Custom DocType `Surgery Set Type`
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

### 15 — Standard Sale Workflow Gap Analysis *(Historical — Superseded by Doc 16)*
**File**: `15-standard-sale-workflow-gap-analysis.md`
> **⚠️ This document captured the gaps between the old standard sale flow (Doc 09) and the stated requirement of fully automated task chains. All gaps identified here were resolved by the Unified Dispatch Flow (Doc 16). Retained for historical reference only.**

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

### 16B — Unified Dispatch Flow Gap Analysis
**File**: `16b-unified-dispatch-flow-gap-analysis.md`
- **Purpose**: Deployment gap analysis — what was needed vs. what existed, deployment progress, and final state after `doc16a-deploy.ps1`.

---

## 4) Future phase documents (explicitly deferred)
These docs are planned later (not required for initial go-live):

### F1 — Costing and Other Expenses (Landed Cost, etc.)
**Planned file**: `F3-costing-and-expenses.md`

## 5) Status / workflow rule
We will draft and modify individual process docs (Doc 11, Doc 12, etc.) only when you explicitly approve.
