# Delivery Driver Guide

**Purpose:** Simple step-by-step reference for the Delivery Driver role. Covers everything you need to do in ERPNext for deliveries and return pickups. You only ever work from your Task inbox — you do not need to open any other part of the system.

**Your role in the system:** `Delivery Driver`

---

## Your task inbox

Every task assigned to you appears in your **Task** list. Open ERPNext, then:
- Click the search bar → type **Task** → press Enter
- Filter: **Status = Open** — this shows everything you need to act on today

You will see two types of tasks:
- **Delivery tasks** — items to bring from the warehouse to a client
- **Return Pickup tasks** — items to collect from a client and bring back to the warehouse

---

## Part A — Delivery

### Step 1 — Find your Delivery task

1. Search for `Task` and open the **Task** list → filter **Task Kind = Delivery**, **Status = Open**.
2. Find the task with your name in the **Assigned To** field.
   - If no tasks are assigned to you personally, look for tasks assigned to `Delivery Team` — ask your coordinator which one is yours.
3. Open the task. Read the **Subject** to confirm the customer and Case ID (e.g. `Deliver: DC-2026-00042 — Dr. A. Petrosyan`).

The task shows:
- Customer name and delivery address / location
- Items and quantities you are delivering
- A **Delivery Status** field (starts at `Todo`)

---

### Step 2 — Mark as Picked Up (when you take the box from the warehouse)

When you physically pick up the packed box from the warehouse:

1. On the task, find the **Delivery Status** field.
2. Change it to **`Picked Up`**.
3. Click **Save**.

**That's all for this step.** The system records that the items are now with you.

---

### Step 3 — Mark as Delivered (when you hand items to the client)

After the client receives the items:

1. On the task, **attach the delivery photo** (required — you cannot mark as Delivered without a photo):
   - Click the 📎 attachment icon on the task form
   - Take a photo of the handover moment (items with the client, or client signing/receiving) and upload it
2. Fill in the **Driver Handover Note** field:
   - Write the name and role of the person who received the items
   - Example: `Received by Dr. Petrosyan's nurse, Ana Sargsyan, at Erebuni MC reception`
3. Change **Delivery Status** to **`Delivered`**.
4. Click **Save**.

**✅ What happens automatically:**
- Stock moves from in-transit to the client's location in the system
- The next step (invoice or return scheduling) is triggered automatically
- Your task is now complete

**❌ If you see an error:**
- `"Delivery photo is required"` → attach a photo before changing to Delivered
- `"Handover Note is required"` → fill in the handover note field first

---

## Part B — Return Pickup

Return Pickup tasks appear when a client is ready to return items from a surgery case.

You will see **two stages** on a Return Pickup task: first you pick items up at the client, then you drop them off at the warehouse.

---

### Step 4 — Find your Return Pickup task

1. Search for `Task` and open the **Task** list → filter **Task Kind = Pickup Returns**, **Status = Open**.
2. Find the task assigned to you: `Pickup Returns: DC-2026-NNNNN — [Customer]`.
3. The task shows:
   - Customer name and location (where to go to collect the items)
   - Items and quantities expected back
   - Due date (when the pickup is scheduled)
   - A **Pickup Status** field (starts at `Todo`)

---

### Step 5 — Mark as Picked Up (when you collect items from the client)

When you are at the client location and have received the items:

1. Fill in the **Driver Handover Note** field:
   - Write who at the client location handed the items to you
   - Example: `Items handed over by Dr. Petrosyan's assistant at Muratsan Hospital OR Block 2`
2. Change **Pickup Status** to **`Picked Up`**.
3. Click **Save**.

**✅ What happens automatically:**
- Stock moves from the client location to return-pickup-in-transit in the system

---

### Step 6 — Mark as Returned to Warehouse (when you drop items at the warehouse)

When you have physically handed the items to the warehouse team:

1. On the task, **attach the drop-off photo** (required — you cannot mark as Returned to Warehouse without a photo):
   - Take a photo of the items being handed over at the warehouse
   - Click the 📎 attachment icon → upload the photo
2. Change **Pickup Status** to **`Returned to Warehouse`**.
3. Click **Save**.

**✅ What happens automatically:**
- Stock moves into the warehouse returns area in the system
- The Returns team is notified to inspect the items
- Your task is complete

**❌ If you see an error:**
- `"Drop-off photo is required"` → attach the warehouse drop-off photo before saving

---

## Summary — what you do and when

| When | Action in ERPNext |
|---|---|
| You pick up delivery box from warehouse | Delivery task → Status = `Picked Up` → Save |
| You hand items to the client | Delivery task → attach photo + fill handover note → Status = `Delivered` → Save |
| You collect return items from client | Return Pickup task → fill handover note → Status = `Picked Up` → Save |
| You drop return items at warehouse | Return Pickup task → attach photo → Status = `Returned to Warehouse` → Save |

---

## Quick rules

- **Always attach a photo** before marking as Delivered or Returned to Warehouse — the system will not let you proceed without it
- **Always fill the handover note** — write the name of the person who received or handed over the items
- **Do not skip steps** — if you mark Delivered without first marking Picked Up, the task history will be incomplete
- **If the task is not in your list** — ask your coordinator to assign it to you; do not take actions on tasks assigned to someone else without coordinator approval
- **If something goes wrong during delivery** (e.g. client not available, items damaged) — do not mark as Delivered; call your coordinator for instructions before doing anything in the system
