# Phase 1 Analysis: Surgery Case Walkthrough Requirements

## Current Issues Found

### 1. **CRITICAL: Permission Errors** ❌
**Problem:** `Ops - Order Creating` and `Ops - Order Accepting` roles cannot create/edit Tasks or select Customers
**Impact:** Step 1 and Step 2 completely blocked
**Fix needed:** Grant permissions via Role Permission Manager

### 2. **CRITICAL: frappe.as_json() Errors** ❌
**Problem:** Server scripts use `frappe.as_json()` which doesn't exist in ERPNext
**Impact:** Dispatch Case submit fails, Task creation fails
**Status:** Fixed in code, needs deployment
**Files:** `doc16a-deploy.ps1`

### 3. **Task Kind Validation Error** ❌
**Problem:** Task Kind field has trailing spaces in options
**Impact:** Validation errors when creating tasks
**Fix needed:** Clean up Task Kind options

### 4. **Task Product Lines Missing** ⚠️
**Problem:** Step 1 expects Task to have product lines, but walkthrough doesn't mention adding them
**Impact:** Step 2 "Create Dispatch Case from Task" button won't work without product lines
**Fix needed:** Update Step 1 instructions

---

## Required Components Checklist

### Roles (from walkthrough)
- ✅ `Ops - Order Accepting` - exists
- ✅ `Ops - Order Creating` - exists
- ✅ `Ops - Directors` - exists
- ✅ `Ops - Inventory` - exists
- ✅ `Delivery Driver` - exists
- ✅ `Ops - Returns` - exists
- ✅ `Ops - Accounting` - exists
- ✅ `Ops - Finance` - exists

### DocTypes Required
- ✅ Task - exists
- ✅ Task Product Line - exists (custom)
- ✅ Dispatch Case - exists (custom)
- ✅ Dispatch Case Item - exists (custom)
- ✅ Customer - exists (standard)
- ✅ Collection Set - needs verification
- ✅ Stock Entry - exists (standard)
- ✅ Sales Invoice - exists (standard)
- ✅ Payment Entry - exists (standard)

### Custom Fields Required

**Task:**
- ✅ `task_kind` - Select field
- ✅ `customer` - Link to Customer
- ✅ `dispatch_case` - Link to Dispatch Case
- ✅ `delivery_status` - Select (Todo/Picked Up/Delivered)
- ✅ `pickup_status` - Select (Todo/Picked Up/Returned to Warehouse)
- ✅ `warehouse_pickup_photo` - Attach
- ✅ `warehouse_dropoff_photo` - Attach
- ✅ `driver_handover_note` - Small Text
- ✅ `approval_outcome` - Select (Approved/Rejected)
- ✅ `return_pickup_driver` - Link to User
- ✅ `scheduled_return_date` - Date
- ✅ `custom_product_lines` - Table (Task Product Line)

**Dispatch Case:**
- ✅ `customer` - Link
- ✅ `client_location_warehouse` - Link to Warehouse
- ✅ `return_expected` - Check
- ✅ `surgery_date` - Date
- ✅ `surgery_set_type` - Link to Collection Set
- ✅ `status` - Select (14 states)
- ✅ `case_items` - Table (Dispatch Case Item)
- ✅ `pack_task` - Link to Task
- ✅ `delivery_task` - Link to Task
- ✅ `return_waiting_task` - Link to Task
- ✅ `return_pickup_task` - Link to Task
- ✅ `returns_inspection_task` - Link to Task
- ✅ `restock_task` - Link to Task
- ✅ `invoice_task` - Link to Task
- ✅ `discount_approval_task` - Link to Task
- ✅ Stock Entry links (dispatch, delivery, consumption, return pickup, return receive, restock)
- ✅ `sales_invoice` - Link to Sales Invoice
- ✅ `prepaid_amount` - Currency
- ✅ `total_invoice_amount` - Currency
- ✅ `total_paid_amount` - Currency
- ✅ `outstanding_amount` - Currency

**Dispatch Case Item:**
- ✅ `item_code` - Link to Item
- ✅ `item_name` - Data
- ✅ `dispatched_qty` - Float
- ✅ `serial_no` - Small Text
- ✅ `batch_no` - Link to Batch
- ✅ `unit_price` - Currency
- ✅ `discount_pct` - Percent
- ✅ `returned_qty` - Float
- ✅ `lost_damaged_qty` - Float
- ✅ `used_qty` - Float (computed)

### Server Scripts Required

1. ✅ **Dispatch Case Before Save** - compute used_qty, detect discount
2. ✅ **Dispatch Case After Save** - create Discount Approval task
3. ❌ **Dispatch Case Before Submit** - validate + create Pack task (HAS BUG: frappe.as_json)
4. ✅ **Task Before Save** - policy/governance checks
5. ❌ **Task After Save** - dispatch flow automation (HAS BUG: frappe.as_json)
6. ✅ **Debt Collection Task Before Save** - payment processing

### Client Scripts Required

1. ✅ **Task - Product Lines Display** - "Create Dispatch Case from Task" button
2. ✅ **Dispatch Case - Price Visibility** - hide prices from non-accounting users
3. ✅ **Dispatch Case - Packing Scan** - barcode scanning for packing

### Permissions Required

**Task DocType:**
- ❌ `Ops - Order Accepting`: Read, Write, Create
- ❌ `Ops - Order Creating`: Read, Write, Create
- ❌ `Ops - Inventory`: Read, Write
- ❌ `Delivery Driver`: Read, Write
- ❌ `Ops - Returns`: Read, Write
- ❌ `Ops - Accounting`: Read, Write
- ❌ `Ops - Finance`: Read, Write
- ❌ `Ops - Directors`: Read, Write, Create, Delete

**Customer DocType:**
- ❌ `Ops - Order Accepting`: Read
- ❌ `Ops - Order Creating`: Read
- ❌ All other roles: Read

**Dispatch Case DocType:**
- ❌ `Ops - Order Creating`: Read, Write, Create, Submit
- ❌ `Ops - Inventory`: Read, Write
- ❌ `Ops - Returns`: Read, Write
- ❌ `Ops - Accounting`: Read, Write
- ❌ `Ops - Finance`: Read
- ❌ `Ops - Directors`: Read, Write, Submit, Cancel

---

## Immediate Fixes Needed

### Fix 1: Deploy doc16a with json.dumps fix
**Status:** Code fixed, needs deployment
**Command:** `.\doc16a-deploy.ps1 -Mode Deploy`

### Fix 2: Grant Task permissions
**Method:** Manual via Role Permission Manager (automated script failed)
**Steps:**
1. Login as Administrator
2. Role Permission Manager → Task
3. Grant permissions to all operational roles

### Fix 3: Grant Customer read permissions
**Method:** Manual via Role Permission Manager
**Steps:**
1. Role Permission Manager → Customer
2. Grant Read to all operational roles

### Fix 4: Update Step 1 in walkthrough
**Issue:** Step 1 doesn't mention adding product lines to Task
**Fix:** Add instruction to add items to `custom_product_lines` table

---

## Next Steps

1. ✅ Deploy doc16a-deploy.ps1 (fixes frappe.as_json bug)
2. ⏳ Fix permissions manually
3. ⏳ Verify all server scripts are enabled
4. ⏳ Update walkthrough Step 1
5. ⏳ Create permission deployment script (for future)

---

## Estimated Time to Fix
- Deploy scripts: 2 minutes
- Fix permissions manually: 5-10 minutes
- Update walkthrough: 2 minutes
- **Total: ~15 minutes**

After these fixes, the walkthrough should work end-to-end.
