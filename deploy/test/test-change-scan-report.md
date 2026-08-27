# Test ERPNext Change Scan Report

Generated from read-only REST scans of `https://test.erpnext.am` on 2026-07-29.

## Safety Scope

- Target environment: Test only (`https://test.erpnext.am`).
- No ERPNext records were modified.
- No production environment was touched.
- Scan compared live Test records against local repo export files under `deploy/test/schema/`.

## Summary

Live Test contains customization drift from the local repo export in these categories:

| Category | Repo Count | Live Count | Added | Changed | Removed |
|---|---:|---:|---:|---:|---:|
| Client Script | 31 | 35 | 4 | 8 | 0 |
| Server Script | 55 | 57 | 2 | 8 | 0 |
| Custom Field | 132 | 134 | 2 | 8 | 0 |
| Property Setter | 208 | 209 | 1 | 2 | 0 |
| Custom DocType | 14 | 19 | 5 | 0 | 0 |
| Workflow | 1 | 1 | 0 | 0 | 0 |
| Report | 49 | 49 direct-confirmed | 0 | 0 | 0 |
| Workspace | 23 | 22 direct-confirmed | 0 | 1 | 1 |

## Client Scripts

### Added

#### `Dispatch Case-Template Auto Fill`

- Enabled: `1`
- DocType: `Dispatch Case`
- View: `Form`
- Script size: 49 lines, 2119 chars
- First line: `frappe.ui.form.on('Dispatch Case', {`

#### `Task - Load Surgical Kit Template`

- Enabled: `1`
- DocType: `Task`
- View: `Form`
- Script size: 34 lines, 1337 chars
- First line: `frappe.ui.form.on('Dispatch Case', {`

#### `Task-Account Details UI Cleanup`

- Enabled: `1`
- DocType: `Task`
- View: `Form`
- Script size: 276 lines, 14029 chars
- Contains:
  - `custom_account_photos`: yes
  - `Account details`: yes
  - `Accept / Start Task`: yes
  - `accounting.team@example.com`: no
  - `custom_assigned_to`: no
- Meaning: Account Details UI/photo/accept-button behavior is client-side, but default assignment is not here.

#### `Task-List Toggle Filters`

- Enabled: `1`
- DocType: `Task`
- View: `List`
- Script size: 79 lines, 3692 chars
- Contains:
  - `My Tasks`: yes
  - `Open Tasks`: yes
  - `Completed`: yes
  - `task_list_filtered`: no
  - `set_route`: no
- Meaning: Task list toggle UI exists; server filtering logic is elsewhere.

### Changed

#### `Dispatch Case-Item Code Toggle`

- Enabled changed: `1 -> 0`
- DocType: `Dispatch Case`
- View: `Form`
- Repo size: 70 lines, 2553 chars
- Live size: 36 lines, 1233 chars
- Changed line ranges: `1-70`
- Important: this script is disabled on Test.

#### `Dispatch Case-Packing Scan`

- Enabled: `1`
- DocType: `Dispatch Case`
- View: `Form`
- Repo size: 178 lines, 6980 chars
- Live size: 178 lines, 7000 chars
- Changed line ranges: `50`, `53`, `56`, `59`, `139`

#### `Dispatch Case-Products Button`

- Enabled: `1`
- DocType: `Dispatch Case`
- View: `Form`
- Repo size: 225 lines, 13014 chars
- Live size: 233 lines, 13593 chars
- Changed line ranges: `96-233`

#### `Global-Mobile Back Button`

- Enabled: `1`
- DocType: `Task`
- View: `Form`
- Repo size: 38 lines, 1844 chars
- Live size: 39 lines, 1913 chars
- Changed line ranges: `6-39`

#### `Task-Accept Start`

- Enabled: `1`
- DocType: `Task`
- View: `Form`
- Repo size: 260 lines, 15066 chars
- Live size: 287 lines, 16772 chars
- Changed line ranges: `49`, `111-287`
- Contains:
  - `Account details`: yes
  - `accept`: yes
  - `dispatch_task_accept`: yes
  - `add_custom_button`: yes
  - `save`: yes
- Meaning: Accept / Start Task behavior was changed, including Account Details handling and save-before-accept indicators.

#### `Task-Dispatch Packing Usability`

- Enabled: `1`
- DocType: `Task`
- View: `Form`
- Repo size: 31 lines, 1556 chars
- Live size: 29 lines, 1407 chars
- Changed line ranges: `3-31`

#### `Task-Product Lines Display`

- Enabled: `1`
- DocType: `Task`
- View: `Form`
- Repo size: 73 lines, 3303 chars
- Live size: 74 lines, 3364 chars
- Changed line ranges: `3-74`

#### `Task-Product Work Area`

- Enabled: `1`
- DocType: `Task`
- View: `Form`
- Repo size: 339 lines, 15831 chars
- Live size: 340 lines, 15906 chars
- Changed line ranges: `115-340`

## Server Scripts

### Added

#### `Task-Account Details Default Assignment`

- Disabled: `0`
- Type: `DocType Event`
- Reference DocType: `Task`
- Event: `Before Save`
- Script size: 24 lines, 909 chars
- First line: `if doc.get("task_kind") == "Account details":`
- Contains:
  - `Account details`: yes
  - `accounting.team@example.com`: yes
  - `custom_assigned_to`: yes
  - `_assign`: yes
  - `ToDo`: yes
- Meaning: default Account Details assignment to accounting team is server-side.

#### `Telegram Task Assignment Notification`

- Disabled: `0`
- Type: `DocType Event`
- Reference DocType: `ToDo`
- Event: `After Insert`
- Script size: 69 lines, 2941 chars
- First line: `# Triggers automatically on any task assignment across all workflows`
- Contains:
  - `Telegram Settings`: yes
  - `bot_token`: yes
  - `chat_id`: yes
  - `requests`: no
  - `Telegram Notification User`: no exact string match
- Meaning: Telegram assignment notifications exist and avoid direct `requests` usage.

### Changed

#### `Dispatch-Case-after-save`

- Disabled: `0`
- Type: `DocType Event`
- Reference DocType: `Dispatch Case`
- Event: `After Save`
- Repo size: 30 lines, 1555 chars
- Live size: 30 lines, 1560 chars
- Changed line ranges: `10`

#### `doc15_norm_reorder_daily_notifications`

- Disabled: `0`
- Type: `Scheduler Event`
- Repo size: 40 lines, 1745 chars
- Live size: 40 lines, 1755 chars
- Changed line ranges: `24`

#### `Payment Entry-after-submit-distribute-payment`

- Disabled: `1`
- Type: `DocType Event`
- Reference DocType: `Payment Entry`
- Event: `After Submit`
- Repo size: 76 lines, 2354 chars
- Live size: 76 lines, 2359 chars
- Changed line ranges: `67`

#### `Scheduled-debt-collection`

- Disabled: `0`
- Type: `Scheduler Event`
- Repo size: 116 lines, 3538 chars
- Live size: 116 lines, 3543 chars
- Changed line ranges: `105`

#### `task_list_filtered`

- Disabled: `0`
- Type: `API`
- API Method: `task_list_filtered`
- Repo size: 100 lines, 4240 chars
- Live size: 108 lines, 4515 chars
- Changed line ranges: `18-44`, `46-95`, `97-108`
- Contains:
  - `task_kind`: yes
  - `roles`: yes
  - `frappe.response`: yes
  - `custom_assigned_to`: no
  - exact text `team-available`: no
- Meaning: server-side Task list filtering logic changed.

#### `Task-after-save-debt-closure`

- Disabled: `0`
- Type: `DocType Event`
- Reference DocType: `Task`
- Event: `After Save`
- Repo size: 94 lines, 5343 chars
- Live size: 94 lines, 6303 chars
- Changed line ranges: `14`, `73`

#### `Task-after-save-dispatch-flow`

- Disabled: `0`
- Type: `DocType Event`
- Reference DocType: `Task`
- Event: `After Save`
- Repo size: 275 lines, 15610 chars
- Live size: 282 lines, 16141 chars
- Changed line ranges: `81`, `91-237`, `239-282`
- Contains:
  - `source_task`: yes
  - `custom_next_task_assign_to`: yes
  - `make_task`: yes
  - `_assign`: yes
  - `ToDo`: yes
- Meaning: next-task assignment routing from source task is present on Test.

#### `Task-before-save-policy`

- Disabled: `0`
- Type: `DocType Event`
- Reference DocType: `Task`
- Event: `Before Save`
- Repo size: 76 lines, 5067 chars
- Live size: 77 lines, 5148 chars
- Changed line ranges: `23-77`

## Custom Fields

### Added

#### `Task-custom_next_task_assign_to`

- DocType: `Task`
- Fieldname: `custom_next_task_assign_to`
- Label: `Next Task: Assign To`
- Fieldtype: `Link`
- Options: `User`
- Insert after: `custom_assigned_to`
- Required: `0`
- Hidden: `0`
- Read only: `0`
- In list view: `0`
- In standard filter: `0`
- Bold: `0`
- Permlevel: `0`

#### `Task-custom_select_surgical_kit_template`

- DocType: `Task`
- Fieldname: `custom_select_surgical_kit_template`
- Label: `Select Surgical Kit Template`
- Fieldtype: `Link`
- Options: `Surgical Kit Template`
- Insert after: `surgery_case`
- Required: `0`
- Hidden: `1`
- Read only: `0`
- In list view: `1`
- In standard filter: `0`
- Bold: `0`
- Permlevel: `0`

### Changed

#### `Task-custom_account_details_section`

- `depends_on`: `eval:doc.task_kind === "Account details" -> eval:doc.task_kind === "__never_show_account_details_documents__"`
- `hidden`: `0 -> 1`

#### `Task-custom_account_photos`

- `label`: `Photos / Documents -> Photos`

#### `Task-custom_assigned_to`

- `label`: `Assigned To (User) -> Assign To`

#### `Task-custom_is_team_queue_task`

- `insert_after`: `task_kind -> custom_next_task_assign_to`

#### `Task-custom_team_notified`

- `hidden`: `0 -> 1`

#### `Task-custom_team_queue_role`

- `insert_after`: `custom_assigned_to -> custom_is_team_queue_task`

#### `Task-dispatch_case`

- `insert_after`: `surgery_case -> custom_select_surgical_kit_template`

#### `Task-sales_invoice`

- `depends_on` was expanded to include `Returns processing / verification`.
- Old expression:
  - `eval:!doc.task_kind || doc.task_kind=="Invoice preparation / create invoice" || doc.task_kind=="Debt Collection" || doc.task_kind=="Payment Received" || doc.task_kind=="Distribute Payment"`
- New expression:
  - same as old plus `|| doc.task_kind=="Returns processing / verification"`

## Property Setters

### Added

#### `Purchase Receipt-provisional_expense_account-hidden`

- DocType: `Purchase Receipt`
- Field: `provisional_expense_account`
- Property: `hidden`
- Property type: `Check`
- Value: `1`
- Applies to: `DocField`

### Changed

#### `Task-main-field_order`

- Property: Task form field order.
- The value changed from a JSON field-order list without the assignment UI placement to a list including:
  - `custom_assigned_to`
  - `custom_next_task_assign_to`
- These fields are placed near the top after `task_kind`.
- Meaning: Task layout changed to support current assignment and next-task assignment UI.

#### `Task-main-show_title_field_in_link`

- `property_type`: `Data -> Check`

## Custom DocTypes Added

### `Account Detail Attachment`

- Module: `Projects`
- Child table: yes
- Single: no
- Submittable: no
- Editable grid: yes
- Fields:
  1. `photo` — Label: `Photo / Document`, Type: `Attach Image`, Required: `0`, Hidden: `0`, In List: `0`
  2. `description` — Label: `Description`, Type: `Data`, Required: `0`, Hidden: `0`, In List: `1`
- Permissions: none

### `Surgical Kit Template`

- Module: `Stock`
- Child table: no
- Single: no
- Submittable: no
- Autoname: `field:template_name`
- Editable grid: no
- Fields:
  1. `template_name` — Label: `Template Name`, Type: `Data`, Required: `1`, Hidden: `0`, In List: `1`
  2. `describtion` — Label: `Description`, Type: `Small Text`, Required: `0`, Hidden: `0`, In List: `0`
  3. `template_items` — Label: `Template Items`, Type: `Table`, Options: `Surgical Kit Template Item`, Required: `0`, Hidden: `0`, In List: `0`
- Permissions:
  - `System Manager`: read/write/create/delete
- Note: fieldname is misspelled as `describtion` on live Test.

### `Surgical Kit Template Item`

- Module: `Stock`
- Child table: yes
- Single: no
- Submittable: no
- Editable grid: yes
- Fields:
  1. `item_code` — Label: `Item Code`, Type: `Link`, Options: `Item`, Required: `0`, Hidden: `0`, In List: `1`
  2. `item_name` — Label: `Item Name`, Type: `Data`, Required: `0`, Hidden: `0`, In List: `1`
  3. `qty` — Label: `Qty`, Type: `Float`, Required: `0`, Hidden: `0`, In List: `1`
- Permissions: none

### `Telegram Notification User`

- Module: `Core`
- Child table: no
- Single: no
- Submittable: no
- Autoname: `field:erp_user`
- Fields:
  1. `erp_user` — Label: `ERP User`, Type: `Link`, Options: `User`, Required: `0`, Hidden: `0`, In List: `0`
  2. `chat_id` — Label: `Chat ID`, Type: `Data`, Required: `0`, Hidden: `0`, In List: `1`
- Permissions:
  - `System Manager`: read/write/create/delete

### `Telegram Settings`

- Module: `Integrations`
- Child table: no
- Single: yes
- Submittable: no
- Fields:
  1. `bot_token` — Label: `Bot Token`, Type: `Password`, Required: `0`, Hidden: `0`, In List: `0`
- Permissions:
  - `System Manager`: read/write/create/delete

## Workflows

- Repo count: 1
- Live count: 1
- No detected workflow drift.

## Reports

Initial list scan appeared to show many missing reports, but direct API checks by report name confirmed:

- Checked reports: 49
- Missing by direct API: 0

Conclusion: reports are not deleted from Test. The earlier report-list count difference was an API listing/filter artifact.

## Workspaces

Direct checks found:

- Checked workspaces: 23
- Missing direct: 1
- Changed metadata: 1

### Missing

- `Tasks`

### Changed

#### `Ops — Reporting Pack`

- Repo title: `Ops — Reporting Pack`
- Live title: `Ops â Reporting Pack`
- Meaning: likely encoding issue around the em dash.

## Practical Feature Groups

### Account Details Task

Related records:

- `Task-Account Details UI Cleanup`
- `Task-Account Details Default Assignment`
- `Account Detail Attachment`
- `Task-custom_account_details_section`
- `Task-custom_account_photos`

Behavior present on Test:

- Account Details has special UI cleanup.
- Photo field label changed to `Photos`.
- Old account details section is hidden by forced false `depends_on`.
- Default assignment to `accounting.team@example.com` is server-side.
- Accept / Start Task behavior is present for Account Details.

### Assignment UI / Next Task Assignment

Related records:

- `Task-custom_assigned_to`
- `Task-custom_next_task_assign_to`
- `Task-main-field_order`
- `Task-after-save-dispatch-flow`

Behavior present on Test:

- Current task assignment field label changed to `Assign To`.
- New `Next Task: Assign To` field exists.
- Task layout places assignment fields near the top.
- Dispatch flow contains `source_task` and `custom_next_task_assign_to`, so next task creation can use assignment from the source task.

### Task List Toggle Filters

Related records:

- `Task-List Toggle Filters`
- `task_list_filtered`

Behavior present on Test:

- Task List has `My Tasks`, `Open Tasks`, and `Completed` toggles.
- Server API `task_list_filtered` changed and contains role/task-kind filtering markers.

### Surgical Kit Template

Related records:

- `Surgical Kit Template`
- `Surgical Kit Template Item`
- `Task-custom_select_surgical_kit_template`
- `Dispatch Case-Template Auto Fill`
- `Task - Load Surgical Kit Template`

Behavior present on Test:

- Surgical kit templates exist.
- Template items include item code, item name, and qty.
- Task has hidden link field to select a template.
- Dispatch/Task scripts exist for template loading/fill behavior.

### Telegram Notifications

Related records:

- `Telegram Settings`
- `Telegram Notification User`
- `Telegram Task Assignment Notification`

Behavior present on Test:

- Telegram bot token is stored in a Single DocType password field.
- Telegram notification users can store ERP user and chat ID.
- ToDo creation can trigger assignment notification logic.

## Notable Risks / Things To Remember

- `Dispatch Case-Item Code Toggle` is disabled on Test.
- `Surgical Kit Template.describtion` is misspelled on Test.
- `Tasks` Workspace is missing by direct API check.
- `Ops — Reporting Pack` title has an encoding issue: `Ops â Reporting Pack`.
- `Task-main-field_order` changed and affects Task layout.
- Reports are not missing despite the first list scan suggesting that.

## Follow-up Change: Dispatch Case Surgical Kit Template Selector

Applied on 2026-07-29 to local script and Test only.

Local repeatable script:

- `deploy/test/show-dispatch-surgical-kit-template.ps1`

Scoped Test changes:

- Restored existing `Dispatch Case.surgery_set_type` back to label `Item Template` and link target `Collection Set` after the first attempt reused the wrong field.
- Created real `Custom Field` record `Dispatch Case-custom_select_surgical_kit_template`.
- New field details: `Dispatch Case.custom_select_surgical_kit_template`, label `Select Surgical Kit Template`, type `Link`, options `Surgical Kit Template`, inserted after `surgery_set_type`, hidden `0`.
- Patched only `Client Script` record `Dispatch Case-Template Auto Fill`.
- New script listens to `custom_select_surgical_kit_template`, fetches `Surgical Kit Template`, reads `template_items`, and fills `Dispatch Case.case_items`.
- Removed old assumptions from that script about `Dispatch Case Template`, `template`, `items`, `Collection Set`, and `surgery_set_type`.

Verification:

- Form metadata for `Dispatch Case` includes `custom_select_surgical_kit_template` with label `Select Surgical Kit Template`, options `Surgical Kit Template`, hidden `0`.
- Existing `Dispatch Case.surgery_set_type` is back to label `Item Template`, options `Collection Set`.
- `Dispatch Case-Template Auto Fill` is enabled for `Dispatch Case` Form.
- Script contains `Surgical Kit Template`, `template_items`, `case_items`, and `custom_select_surgical_kit_template`.
- Script no longer contains `Collection Set`, `Dispatch Case Template`, or `surgery_set_type`.

## Follow-up Change: Account Details Assign To Box

Applied on 2026-07-29 to local script and Test only.

Local repeatable script:

- `deploy/test/fix-account-details-assign-box.ps1`

Scoped Test changes:

- Patched only `Client Script` record `Task-Account Details UI Cleanup`.
- The Account Details cleanup now keeps `Task.custom_assigned_to` visible instead of hiding it with the status-section cleanup.
- It appends the `Assign To` control into the same compact Account Details left column as `Status` and `Priority`.
- It did not change photo handling, Accept / Start Task logic, subject generation, product fields, task list filters, or dispatch flow.

Verified unchanged server rule:

- `Task-Account Details Default Assignment` already uses `doc.get("custom_assigned_to") or "accounting.team@example.com"`.
- Meaning: selected `Assign To` user/team wins; empty assignment defaults to `accounting.team@example.com`.

Verification:

- Live `Task-Account Details UI Cleanup` contains `custom_assigned_to` and `assignedControl`.
- Live `Task-custom_assigned_to` label is `Assign To`, hidden `0`, read-only `0`, options `User`.
- Live server default assignment rule is still present.

## Completion Status

This report preserves the read-only scan results locally so they are not only stored in chat context.
