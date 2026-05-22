# Dispatch Case Packing Enhancements Plan

## Purpose

This plan prepares ERPNext changes for warehouse packing work where the office creates a Dispatch Case with real item rows, and inventory workers scan products while ERPNext tracks what is scanned, what is missing, and whether earlier-expiring stock exists.

## Decisions

| Area | Decision |
|---|---|
| Main operational document | Use `Dispatch Case` |
| Product list location | Use `Dispatch Case Item` child rows, not free text in `Task` |
| Worker task | `Task` tells the worker what job to do and links to the `Dispatch Case` |
| Unassigned work | Use team-queue behavior; a free worker can accept/start a task |
| FEFO | Warning-only, not blocking |
| Stock movement timing | Scanning records packing progress; stock movement remains controlled by the Dispatch Case flow |

## What the deploy script prepares

Files:

```text
deploy/dispatch-packing-enhancements-deploy.ps1
deploy/dispatch-team-task-queue-deploy.ps1
deploy/dispatch-packing-problem-alerts-deploy.ps1
deploy/dispatch-task-integration-deploy.ps1
```

Each script supports:

```powershell
.\deploy\dispatch-packing-enhancements-deploy.ps1 -Mode Check
.\deploy\dispatch-packing-enhancements-deploy.ps1 -Mode Deploy
```

## Added Dispatch Case fields

| Field | Purpose |
|---|---|
| `custom_packing_scan_barcode` | Scan/input box on Dispatch Case |
| `custom_packing_scan_qty` | Quantity for current scan, default 1 |
| `custom_packing_scan_result` | Last scan result message |
| `custom_packing_last_warning` | Last FEFO or scan warning |

## Added Dispatch Case Item fields

| Field | Purpose |
|---|---|
| `custom_packing_status` | Pending, Partial, Complete, Over Scanned, Problem |
| `custom_scanned_qty` | Quantity already scanned |
| `custom_remaining_qty` | Quantity still missing |
| `custom_last_scanned_barcode` | Last barcode scanned for this row |
| `custom_last_scan_at` | Timestamp of last scan |
| `custom_last_scanned_by` | Worker who last scanned |
| `custom_fefo_warning` | FEFO warning for the row |
| `custom_scan_note` | Manual packing note/problem note |

## Added automation

| Automation | Purpose |
|---|---|
| `dispatch_case_packing_scan` API Server Script | Processes a scan, updates matching Dispatch Case Item row, calculates remaining quantity, and warns if earlier-expiring stock exists |
| `dispatch_task_accept` API Server Script | Lets a worker accept/start an operational task and assigns it to themselves |
| `Dispatch Case-Packing Scan` Client Script | Adds scan button and scan field behavior on Dispatch Case |
| `Task-Accept Start` Client Script | Adds `Accept / Start Task` button on Task |
| `Task-team-queue-notify` Server Script | Marks operational tasks as team queue tasks and creates role-based ToDo notifications |
| `Task-Team Queue` Client Script | Adds a Task list team queue filter button and accept/start behavior |
| `Dispatch Case-packing-problem-alerts` Server Script | Creates manager/director ToDo alerts when packing rows are incomplete or marked Problem |
| `Task-dispatch-queue-integration` Server Script | Keeps Dispatch Case operational tasks integrated with team queue status/role fields |
| `dispatch_task_queue_backfill` API Server Script | Repairs existing open Dispatch Case tasks so they use team queue fields |

## Worker flow after deployment

1. Office creates a `Dispatch Case`.
2. Office adds real item rows in `Case Items`.
3. ERPNext creates or shows the packing `Task`.
4. Inventory worker searches for `Task` and uses `My Team Queue` to see available team tasks.
5. Worker clicks `Accept / Start Task`.
6. Worker opens the linked `Dispatch Case`.
7. Worker scans product barcodes in `Packing Scan Barcode`.
8. ERPNext updates scanned and remaining quantities.
9. If earlier expiry stock exists, ERPNext warns but does not block.
10. If items are missing or a row is marked Problem, ERPNext opens a packing problem and creates manager/director ToDo alerts.
11. Worker continues until every required item row is complete.

## FEFO behavior

If the worker scans a batch with a later expiry and ERPNext finds earlier-expiring available stock for the same item in `Main - Inmed`, it shows a warning like:

```text
FEFO warning only: earlier-expiring stock exists in Main - Inmed. Consider using first: LOT123 exp 2026-03-01 qty 2
```

The scan is still accepted because FEFO is warning-only.

## Important limitations of this first phase

- This prepares packing progress and warning behavior.
- It does not yet create a custom full-screen mobile packing page.
- It does not yet send external phone/email notifications.
- ERPNext in-app assignment/ToDo notification behavior still depends on ERPNext notification settings.

## Deployed status

As of the Step 1-3 deployment, ERPNext has:

- Packing scan/progress fields and FEFO warning-only scan logic.
- Team task queue fields and `Accept / Start Task` behavior.
- Role-based ERPNext `ToDo` notifications for team queue tasks.
- Packing shortage/problem fields and manager/director `ToDo` alerts.
- Dispatch Case task integration so future operational tasks receive queue role/status.

## Testing after deployment

1. Run the deploy script in `Check` mode.
2. If the check result is acceptable, run `Deploy` mode.
3. Open ERPNext and search for `Dispatch Case`.
4. Create a test Dispatch Case with 1-2 item rows.
5. Submit/save according to the current flow so a packing Task exists.
6. Search for `Task`, open the packing task, and click `Accept / Start Task`.
7. Return to the linked Dispatch Case.
8. Scan a product/item barcode.
9. Confirm `Scanned Qty`, `Remaining Qty`, `Packing Status`, and warning fields update.
10. Test one batch item with earlier-expiring stock to confirm FEFO warning appears without blocking.
