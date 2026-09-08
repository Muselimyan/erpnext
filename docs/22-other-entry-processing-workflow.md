# Doc 22 — Other: Entry / Other: Processing Workflow

## 1) Purpose

This document defines how **Other: Entry** and **Other: Processing** tasks work. These are the standard task kinds for ad-hoc operational work that does not belong to any specific workflow (dispatch, debt, approvals, account details).

Examples:
- Office supply requests
- Equipment repair requests
- Facility maintenance tasks
- Internal communication follow-ups
- Any miscellaneous operational task

Non-goals:
- This doc does not cover dispatch, delivery, debt, approval, or account-details workflows (see Docs 09, 10, 16, 16a).

---

## 2) Replaces plain "Other" task kind

The legacy **"Other"** task kind (with `other_items` checklist, `other_budget`, and `other_supplier` fields) is retired. All ad-hoc tasks should use the **Entry / Processing** pair instead.

| Old | New |
|---|---|
| Other (plain) — one-step checklist | Other: Entry → Other: Processing (two-step with handoff) |
| `other_items` child table (checklist) | Use standard `description` field |
| `other_budget` currency field | Use `description` field to note budget |
| `other_supplier` link field | Use `description` field to note supplier |

Migration: any existing tasks with `task_kind == "Other"` should be completed or cancelled. After migration, "Other" is removed from the `task_kind` Select options, and its Task Access Policy, custom fields, and child DocType (`Task Other Item`) are deleted.

---

## 3) Roles

| Step | Task kind | Role |
|---|---|---|
| 1 | Create and complete Other: Entry | Any operational role |
| 2 | Accept and complete Other: Processing | Any operational role (assigned by Entry creator) |

All nine operational roles plus Delivery Driver can create, see, accept, and complete both kinds. Default team: `office.team@example.com`.

---

## 4) Workflow overview

```
 User creates task
 (kind = Other: Entry)
        │
        ▼
 ┌──────────────┐
 │ Other: Entry  │  User fills subject, description, photos (optional)
 │               │  Sets "Next Task: Assigned To" for the follow-up
 └──────┬───────┘
        │ completes
        ▼
 ┌──────────────────┐
 │ Other: Processing │  Auto-created by server
 │                    │  Copies: customer, project, description, all attachments
 │                    │  Assigned to: value from "Next Task: Assigned To"
 └──────────────────┘
        │ completes
        ▼
      Done
```

---

## 5) Step 1 — Create Other: Entry

**Login as:** any operational user

1. Open **Task** list, click **New**.
2. Set:
   - **Task Kind:** `Other: Entry`
   - **Subject:** clear description of the request (defaults to "Other: Entry" if left blank)
   - **Description:** full details — what is needed, by when, budget if applicable, supplier if applicable
   - **Customer** (optional): if the task is related to a customer
   - **Next Task: Assigned To:** the person who should handle the follow-up processing
   - **Photos** (optional): attach up to 5 photos using the Task Photos gallery
3. Click **Save** to create the task.
4. Click **Accept / Start Task** (or it is auto-accepted if assigned to you).
5. When done recording the request, click **Complete**.

**What happens on completion:**
- The server automatically creates an **Other: Processing** task (see Step 2).
- The Entry task is linked via the `depends_on` relationship.
- Customer, project, description, and all file attachments are copied to the Processing task.
- If `Next Task: Assigned To` was set, the Processing task is assigned to that person.
- If `Next Task: Assigned To` was empty, the Processing task goes to the default team (`office.team@example.com`).

---

## 6) Step 2 — Complete Other: Processing

**Login as:** the assigned user (or any team member if assigned to team)

1. Find the **Other: Processing** task in your task list.
2. Click **Accept / Start Task** to take ownership.
3. Review the description and attachments copied from the Entry task.
4. Do the work.
5. Add notes to the **Description** field if needed.
6. Attach additional photos if needed.
7. Click **Complete** when done.

**No downstream task is created.** The workflow ends here.

---

## 7) Fields visible for Other: Entry

| Field | Visible? | Editable? | Notes |
|---|---|---|---|
| **Task Kind** | Yes (read-only after save) | No | Locked after creation (Doc 22 §1.2 in visibility redesign) |
| **Subject** | Yes | Yes | Defaults to "Other: Entry" if blank |
| **Description** | Yes | Yes | Standard Frappe field |
| **Customer** | Yes | Yes | Optional |
| **Assigned To** | Yes | Yes (before acceptance) | Standard field |
| **Next Task: Assigned To** | Yes | Yes | Who handles the Processing step |
| **Status** | Yes | Yes | Open → Working → Completed |
| **Priority** | Yes | Yes | Medium by default |
| **Photos** | Yes | Yes | Task Photos gallery, up to 5, optional |
| Product work section | Hidden | — | Not relevant |
| Barcode scanning | Hidden | — | Not relevant |
| Dispatch Case | Hidden | — | Not relevant |
| Approval fields | Hidden | — | Not relevant |
| Payment/debt fields | Hidden | — | Not relevant |

---

## 8) Fields visible for Other: Processing

Same as Other: Entry, except:

| Field | Difference |
|---|---|
| **Next Task: Assigned To** | Hidden — Processing does not create a downstream task |
| **Description** | Pre-filled from Entry task, editable |
| **Photos** | Pre-copied from Entry task, additional photos can be added |

---

## 9) Server scripts

| Script | Event | What it does |
|---|---|---|
| `Task-after-save-other-processing.py` | After Save | On completion of Other: Entry, creates Other: Processing task. Copies customer, project, description, files. Sets assignment from `custom_next_task_assign_to`. Duplicate guard: checks if Processing already exists. |
| `Task-Other Entry Default Subject.py` | Before Save | If subject is blank or generic ("New Task", "Other"), sets it to "Other: Entry" or "Other: Processing". |
| `Task-before-save-policy.py` | Before Save | Generic: reads Task Access Policy, sets default team, enforces role checks. |

---

## 10) Task Description field

The standard Frappe **Description** field (rich text / markdown) is the primary place for details on Other tasks. No custom "notes" or "comment" fields are needed.

**Behavior:**
- **Collapsible by default.** The Description section should be collapsed when the form loads — it does not need to take up screen space until the user expands it.
- **Other: Entry:** The creator writes the full request details here (what is needed, budget, supplier, deadline, context).
- **Other: Processing:** Description is pre-filled from the Entry task. The assignee can add to it as they work.

**In the dispatch flow (for context):**
When a task is part of the dispatch chain (Order entry, Pack, Delivery, etc.), the description is attached to the Dispatch Case at creation. Downstream tasks receive an expanded description that includes the DC context. For Other tasks there is no DC — the description stands alone and flows only from Entry to Processing.

**No custom fields replace it.** The retired `other_budget` and `other_supplier` fields are not replaced by new custom fields. Users should include budget and supplier information in the Description text.

---

## 11) Task Access Policy

| Kind | Default team | Allowed roles |
|---|---|---|
| Other: Entry | `office.team@example.com` | Ops - Order Accepting, Ops - Order Creating, Ops - Inventory, Ops - Returns, Ops - Delivery, Ops - Accounting, Ops - Directors, Ops - Finance, Delivery Driver |
| Other: Processing | `office.team@example.com` | Same as above |

---

## 12) Differences from Account Details: Entry / Processing

The Other pair follows the same Entry → Processing pattern as Account Details, but with key differences:

| | Other | Account Details |
|---|---|---|
| **Purpose** | General ad-hoc work | Document/photo intake and processing |
| **Photos** | Optional (Task Photos gallery) | Core feature (Account Detail Attachment table) |
| **Specific fields** | None beyond standard | `custom_account_photos`, `custom_account_details_subject` |
| **Who creates** | Any operational role | Specific account-details workflow |
| **Completion gate** | None — just click Complete | None currently (no server validation) |

---

## 13) Known gaps and future considerations

1. **No completion validation.** There is no server-side gate requiring description, photos, or any specific field before completing either Entry or Processing. Consider adding a gate if accountability is needed.
2. **Subject defaults are weak.** If the user leaves subject blank, it becomes "Other: Entry" — not very searchable. Consider requiring a meaningful subject.
3. **No link between Entry and Processing on the form.** The Processing task links to Entry via `depends_on`, but there is no visible field on Processing showing "Created from Entry task TASK-XXXX." Consider adding a read-only Link field or showing the dependency prominently.
4. **Photos are optional.** Unlike delivery or pack tasks, there is no photo requirement gate. This is by design for ad-hoc tasks but should be documented as a conscious choice.
