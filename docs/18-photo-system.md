# Doc 18 — Photo System (Task Photos, Completion Gates, and Dispatch Case Galleries)

## 1) Purpose
Define the complete photo requirements for the Task and Dispatch Case systems:
- Which task kinds require, allow, or prohibit photos.
- What users can do with photos (upload, view, delete).
- When photos are required (completion gates).
- How photos are displayed on Tasks and Dispatch Cases.
- Permission rules (who can upload/delete).
- Upload limits.
- Mobile vs desktop behavior.

This doc supersedes the photo-related sections in Doc 10 (sections 7.1, 7.2, 7.3) and provides the single authoritative source for all photo behavior.

This doc describes **requirements and rules**. Implementation details (which scripts, which fields, which API calls) belong in implementation/audit artifacts.

---

## 2) Architecture overview

### 2.1 Source of truth
**File records** are the sole source of truth for photos. A photo exists on a task if and only if a `File` record exists with:
- `attached_to_doctype = "Task"`
- `attached_to_name = <task name>`
- A file URL ending in a known image extension

No Attach fields are used. The legacy fields (`warehouse_pickup_photo`, `warehouse_dropoff_photo`, `custom_delivery_photo`) have been deleted from the Task DocType.

### 2.2 Client-side components
All photo UI is rendered by the **PhotoGallery** module (`Task-Photo-System.js`):
- `PhotoGallery` — reusable, document-agnostic gallery widget
- `PhotoFullscreen` — reusable fullscreen image viewer with zoom/pan/pinch

These are defined on `window` and available globally when a Task form is loaded.

For Dispatch Case galleries, a separate self-contained renderer is used (`Dispatch Case-Photo-Galleries.js`) with its own fallback fullscreen viewer.

### 2.3 Server-side
- Completion gates use `task_has_image(task_name)` — queries File records directly
- No server-side photo propagation between documents
- Dispatch Case photo display is handled entirely client-side via live File record lookup

---

## 3) Confirmed constraints
- Maximum 5 photo attachments per task (for task kinds that support photos).
- Only image files are shown in galleries (`.jpg`, `.jpeg`, `.png`, `.gif`, `.webp`, `.heic`, `.heif`).
- The 5-file limit counts ALL attached files (not just images). This is intentional.
- Photos must not be uploadable before the user has accepted the task.
- Photos must not be deletable by a user who has not accepted the task.
- System Managers and Administrators bypass the acceptance requirement.
- Mobile and desktop must provide the same photo functionality, although layouts may differ.

---

## 4) Photo rules by task kind

### 4.1 Order Entry
**Photos: NONE**

Order Entry is a data-entry task (selecting products, quantities, customer). No physical goods handling occurs. No upload controls should exist.

### 4.2 Pack / Prepare Items
**Photos: REQUIRED for completion**

Purpose: Photographic evidence that items were packed and ready for pickup at `Main - WH`.

Rules:
- Users may attach up to 5 photos.
- Gallery labeled "Warehouse Pickup Photos".
- Users must see thumbnail previews of all attached photos.
- Users must be able to delete photos (if they accepted the task).
- **Completion gate:** The task cannot be marked Completed unless at least one image File record is attached. Checked by `task_has_image(doc.name)` in `before_save`.

### 4.3 Delivery
**Photos: NONE**

The driver picks up packed items and delivers them. No photographic evidence is required on the Delivery task itself.

- No upload controls should exist.
- No completion gate requires a photo.

Note: Doc 10 section 7.1 originally stated that a Delivery task requires a Warehouse Pickup Photo. This has been superseded. The photo requirement belongs on the **Pack** task (which is where packing actually happens), not on the Delivery task.

### 4.4 Pickup Returns
**Photos: REQUIRED for warehouse return**

Purpose: Photographic evidence that items were physically returned to the warehouse.

Rules:
- Users may attach up to 5 photos.
- Gallery labeled "Warehouse Drop-off Photos".
- Users must see thumbnail previews of all attached photos.
- Users must be able to delete photos (if they accepted the task).
- **Completion gate:** When `pickup_status` is set to "Returned to Warehouse", `task_has_image(doc.name)` must return true. If false, the save is blocked with an error.
- Upon passing the gate, the task status is automatically set to Completed.

### 4.5 Returns Processing / Verification
**Photos: READ-ONLY reference display (from Pack task)**

Purpose: The Returns inspector needs to compare what was originally packed/sent versus what was physically returned. The Pack task's photos are displayed as a read-only reference gallery.

Rules:
- No upload mechanism. This task kind does not have its own photos.
- The system fetches ALL image Files attached to the Pack task for the same Dispatch Case.
- These are displayed as a read-only gallery titled "Pack / Prepare Photos".
- Each thumbnail is clickable with fullscreen preview (pinch-to-zoom on mobile).
- If no Pack task photos exist, nothing is rendered.

This is intentional behavior, not a photo leak. Showing Pack photos on the Returns inspection task is a confirmed design decision.

### 4.6 Account Details
**Photos: ALLOWED (not required)**

Purpose: Attach photos or documents related to the client's account (e.g., ID documents, contracts, facility photos).

Rules:
- Users may attach up to 5 photos.
- Users must see thumbnail previews of all attached photos.
- Users must be able to delete photos (if they accepted the task).
- Photos are NOT required for task completion (no server-side gate).
- When an Account Details: Entry task is completed and an Account Details: Processing task is created, photos should be copied to the Processing task so the processing team can see them.

Field: `custom_account_photos` (Photos) — Table field with `Account Detail Attachment` child rows

### 4.7 Other (Entry / Processing)
**Photos: ALLOWED (not required)**

Purpose: General-purpose photo attachments for miscellaneous tasks.

Rules:
- Users may attach up to 5 photos.
- Gallery labeled "Task Photos".
- Users must see thumbnail previews of all attached photos.
- Users must be able to delete photos (if they accepted the task).
- Photos are NOT required for task completion (no server-side gate).

### 4.8 All other task kinds
**Photos: NONE (default)**

Any task kind not listed above should not display photo upload controls or photo galleries. The default behavior is no photos.

---

## 5) Permission model
Photo upload and deletion are gated by task acceptance:

| User state | Can upload | Can delete | Can view |
|---|---|---|---|
| Not logged in | No | No | No |
| Logged in, task not accepted by anyone | No | No | Yes (previews) |
| Logged in, task accepted by a different user | No | No | Yes (previews) |
| Logged in, task accepted by this user | Yes | Yes | Yes |
| System Manager / Administrator | Yes | Yes | Yes |

The acceptance check uses:
- `custom_accepted_by` field on the Task.
- A match against `frappe.session.user`.
- Role check for `System Manager` or `Administrator`.

The locking system (`Task-Lock Unaccepted`) provides a backup safety net by setting the gallery mode to `readonly` when the user has not accepted the task.

---

## 6) Upload behavior
### 6.1 File limit
- Maximum 5 files per task.
- The gallery enforces this client-side before opening the file picker.
- If already at 5, the upload is blocked with: "Maximum 5 photos."

### 6.2 Accepted file types
- The file picker restricts to `image/*` via `accept="image/*"`.
- The gallery filters displayed files to known image extensions: `.jpg`, `.jpeg`, `.png`, `.gif`, `.webp`, `.heic`, `.heif`.

### 6.3 New task handling
- If the task has not been saved yet (`frm.is_new()`), the gallery is not rendered. Photos require a saved task.

### 6.4 Upload mechanism
- Files are uploaded via `fetch('/api/method/upload_file')` as private files in `Home/Attachments`.
- Uploaded files are initially unattached (no `attached_to_doctype`/`attached_to_name`).
- On form save (`after_save`), newly uploaded files are attached to the Task by setting both `attached_to_doctype` and `attached_to_name` atomically via `frappe.client.set_value`.

---

## 7) Deletion behavior
- Each photo thumbnail has a delete button (red "x" circle, top-right corner).
- Delete buttons are only rendered in `editable` mode (user accepted the task, or is admin).
- Clicking delete shows a confirmation dialog: "Remove this photo?"
- On confirmation:
  1. The photo is removed from the gallery's internal list.
  2. The form is marked dirty (triggering save).
  3. On `after_save`, the removed file's `File` record is deleted via `frappe.client.delete`.
- On failure, a retry is attempted. If retry fails, an error is logged.

---

## 8) Dispatch Case photo galleries

The Dispatch Case form displays read-only photo galleries sourced live from linked Tasks.

### 8.1 Galleries

| Gallery | Label | Source Task field | Source |
|---|---|---|---|
| Pickup Photos | Warehouse Pickup Photos | `pack_task` | All image Files attached to the Pack task |
| Drop-off Photos | Warehouse Drop-off Photos | `return_pickup_task` | All image Files attached to the Pickup Returns task |

### 8.2 Behavior
- Galleries fetch image File records from the linked task on every form refresh.
- If the linked task field is empty or the task has no images, **nothing is rendered** (no label, no empty state).
- Galleries are always read-only (no upload, no delete).
- Thumbnails are clickable with fullscreen preview.
- The `photo_section` Section Break on the Dispatch Case form hosts the gallery containers.

### 8.3 No server-side propagation
Photos are NOT copied from Tasks to the Dispatch Case. The DC galleries display live data from the linked tasks. This means:
- Photos always reflect the current state of the source task.
- If a task's photos are updated, the DC view updates on next refresh.
- No stale snapshots or denormalized data.

### 8.4 Order Creation role
The `Dispatch Case-Simplify for Order Creation` script hides the entire photo section for users with the `Ops - Order Creating` role, since photos don't exist yet at order creation time.

---

## 9) Gallery display
### 9.1 Thumbnail galleries
All photo galleries use a consistent visual pattern:
- Label rendered using Frappe's native `.control-label` class (same font/color as other form labels).
- Thumbnails and Add button rendered in a single flex row (`display:flex; flex-wrap:wrap; gap:8px`).
- Thumbnail size: 76x76px with 6px border-radius.
- Each thumbnail is a clickable button that opens fullscreen preview.
- Delete buttons (when in editable mode): 20px red circle, positioned top-right of each thumbnail.
- "+ Add Photos" button appears inline after the last thumbnail (editable mode only).

### 9.2 Fullscreen preview
- Tapping a thumbnail opens a full-screen overlay.
- The overlay includes: image, close button.
- Pinch-to-zoom is supported on touch devices (via PhotoFullscreen).
- Keyboard: Escape closes the overlay.

### 9.3 Empty gallery behavior
- If no images are found and mode is readonly, nothing is rendered (no label, no container).
- If no images are found and mode is editable, only the label and "+ Add Photos" button are shown.

---

## 10) Completion gates summary

| Task kind | Gate trigger | Check | Blocks on |
|---|---|---|---|
| Pack / Prepare Items | Status → Completed | `task_has_image(doc.name)` | `frappe.throw` in `before_save` |
| Pickup Returns | `pickup_status` → "Returned to Warehouse" | `task_has_image(doc.name)` | `frappe.throw` in `before_save` |
| Delivery | (none) | — | — |
| Order Entry | (none) | — | — |
| Returns Processing | (none) | — | — |
| Account Details | (none) | — | — |
| Other | (none) | — | — |

The `task_has_image()` helper queries File records with `attached_to_doctype="Task"` and checks for image extensions. No Attach field values are checked.

---

## 11) Field inventory

### 11.1 Task fields (photo-related)
| Fieldname | Label | Type | Used by |
|---|---|---|---|
| `custom_account_photos` | Photos | Table → Account Detail Attachment | Account Details |

Legacy fields removed: `warehouse_pickup_photo`, `warehouse_dropoff_photo`, `custom_delivery_photo`.

### 11.2 Dispatch Case fields
| Fieldname | Label | Type | Status |
|---|---|---|---|
| `delivery_photo` | Delivery Photo | Attach | Hidden (legacy, no longer populated) |
| `return_dropoff_photo` | Return Drop-off Photo | Attach | Hidden (legacy, no longer populated) |
| `photo_section` | Photos | Section Break | Used as container for live gallery rendering |

### 11.3 Account Detail Attachment (child table)
| Fieldname | Label | Type |
|---|---|---|
| `photo` | Photo / Document | Attach Image |
| `description` | Description | Data |

---

## 12) Implementation files

### 12.1 Client Scripts
| Script | DocType | Purpose |
|---|---|---|
| `Task-Photo-System` | Task | PhotoGallery, PhotoFullscreen, Task form handlers (refresh + after_save) |
| `Dispatch Case-Photo-Galleries` | Dispatch Case | Read-only galleries with live Task File lookup |
| `Task-Lock Unaccepted` | Task | Sets gallery mode based on acceptance state |

### 12.2 Server Scripts
| Script | DocType | Event | Photo role |
|---|---|---|---|
| `Task-before-save-dispatch-gates` | Task | Before Save | Pack/Pickup Returns completion gates via `task_has_image()` |
| `Task-before-save-policy` | Task | Before Save | Policy gates for tasks without Dispatch Case |
| `Stock Entry-before-submit-dispatch-gate` | Stock Entry | Before Submit | Delivery task photo check |

### 12.3 Disabled/Obsolete
| Script | Reason |
|---|---|
| `Task-before-save-return-dropoff-photo` | Replaced by `task_has_image()` in dispatch gates |

---

## 13) Observability
A diagnostic logging system is deployed on the test environment to trace all photo behavior:

### 13.1 Browser-side logging
- All photo-related log lines use a `[Photo]` prefix with subsystem tags (e.g., `[Photo][form]`, `[Photo][gallery]`).
- Logs are enabled by default on test. To silence: `window.PHOTO_DEBUG = false` in the browser console.
- Filter browser console output by `[Photo]` to see all photo-related decisions.

Logged events include:
- Script load confirmation with timestamp.
- Task kind detection and photo configuration selection.
- Permission decisions (accepted by, admin status, canEdit, mode).
- File record queries and results (count, URLs).
- Gallery creation and readiness.
- Upload start, success, failure.
- Remove action.
- After-save reconciliation (added/removed URLs, attach, delete).
- Attach success/failure with File record IDs.
- Delete success/failure with retry.

### 13.2 Server-side logging
- Server scripts log photo-related events using `print()` to stdout with `[Photo]` prefix and timestamp.
- Viewable via: `docker logs frappe-test-backend-1 | grep Photo`

Logged events include:
- `task_has_image()` results: total files, image count, URLs.
- Pack completion gate result (pass/block).
- Pickup Returns drop-off gate result (pass/block).
- Policy gate results for tasks without Dispatch Case.

---

## 14) Relationship to other docs
- **Doc 10** (Task System Foundations): Sections 7.1–7.3 originally defined photo requirements. Doc 18 supersedes those sections with more precise and current rules. The key correction: the pickup photo requirement belongs on Pack tasks, not Delivery tasks.
- **Doc 12** (Surgery Set Operational Workflow): References photo requirements in the context of dispatch/return lifecycle.
