# ERPNext Manual Setup Checklist for System Manager

Use this document before testing the local manuals. It lists the ERPNext setup that should exist so the example users can follow the manuals without permission or missing-master-data blockers.

Do these steps while logged in with your System Manager account.

---

## 1. Purpose

This checklist is for preparing the local ERPNext test system.

It is not for normal daily users. Real users can be configured later after this example setup is confirmed.

Use it to make sure:

- example roles can open the screens used in the manuals
- example users have the correct roles
- purchasing, inventory, accounting, delivery, returns, and director tests are not blocked by missing permissions
- supplier groups, payment terms, and known suppliers exist

---

## 2. Example users to check

Search for `User` and open the **User** list.

Confirm these users exist and are enabled.

| User | Required role or roles |
|---|---|
| `purchasing.team@example.com` | `Ops - Purchasing`, `Ops - Purchasing Lead` |
| `inventory.team@example.com` | `Ops - Inventory` |
| `accounting.team@example.com` | `Ops - Accounting` |
| `directors.team@example.com` | `Ops - Directors` |
| `order.team@example.com` | `Ops - Order Accepting` |
| `delivery.team@example.com` | `Ops - Delivery` |
| `returns.team@example.com` | `Ops - Returns` |
| `driver.01@example.com` | `Delivery Driver` |
| `finance.team@example.com` | `Ops - Finance` |
| `order.creation.team@example.com` | `Ops - Order Creating` |

For each user:

1. Search for `User` and open the **User** list.
2. Open the user.
3. Confirm **Enabled** is checked.
4. Confirm **User Type** is `System User`, except dedicated display-only users if intentionally configured otherwise.
5. In the **Roles** table, add the required role or roles.
6. Save.

---

## 3. Roles that should exist

Search for `Role` and open the **Role** list.

Confirm these roles exist:

- `Ops - Purchasing`
- `Ops - Purchasing Lead`
- `Ops - Inventory`
- `Ops - Accounting`
- `Ops - Directors`
- `Ops - Order Accepting`
- `Ops - Delivery`
- `Ops - Returns`
- `Delivery Driver`
- `Ops - Finance`
- `Ops - Order Creating`

If a role is missing:

1. Search for `Role` and open the **Role** list.
2. Click **New**.
3. Enter the role name exactly.
4. Save.

---

## 4. Permission setup method

Use `Role Permission Manager` for the checks below.

For each row:

1. Search for `Role Permission Manager` and open the **Role Permission Manager** tool.
2. Select the **DocType**.
3. Find or add the row for the role.
4. Set the permissions listed.
5. Save.

After many permission changes, log out and log back in with the example user before testing.

---

## 5. Purchasing permissions

These are needed for `new-supplier-setup.md`, `purchase-walkthrough.md`, and supplier prepayment testing.

| DocType | Role | Permissions |
|---|---|---|
| `Supplier` | `Ops - Purchasing` | Read, Write, Create |
| `Supplier Group` | `Ops - Purchasing` | Read |
| `Contact` | `Ops - Purchasing` | Read, Write, Create |
| `Address` | `Ops - Purchasing` | Read, Write, Create |
| `Payment Terms Template` | `Ops - Purchasing` | Read |
| `Payment Term` | `Ops - Purchasing` | Read |
| `Item` | `Ops - Purchasing` | Read |
| `Item Group` | `Ops - Purchasing` | Read |
| `UOM` | `Ops - Purchasing` | Read |
| `Item Price` | `Ops - Purchasing` | Read |
| `Warehouse` | `Ops - Purchasing` | Read |
| `Purchase Order` | `Ops - Purchasing` | Read, Write, Create, Submit |
| `Task` | `Ops - Purchasing` | Read, Write, Create |

For `Ops - Purchasing Lead`:

| DocType | Role | Permissions |
|---|---|---|
| `Supplier` | `Ops - Purchasing Lead` | Read, Write, Create |
| `Purchase Order` | `Ops - Purchasing Lead` | Read, Write, Create, Submit |
| `Item` | `Ops - Purchasing Lead` | Read, Write |
| `Item Price` | `Ops - Purchasing Lead` | Read, Write, Create |
| `Task` | `Ops - Purchasing Lead` | Read, Write, Create |

---

## 6. Inventory permissions

These are needed for `new-item-setup.md`, receiving, stock adjustment, and warehouse work.

| DocType | Role | Permissions |
|---|---|---|
| `Item` | `Ops - Inventory` | Read, Write, Create |
| `Item Group` | `Ops - Inventory` | Read, Write, Create |
| `Item Attribute` | `Ops - Inventory` | Read, Write, Create |
| `UOM` | `Ops - Inventory` | Read, Write, Create |
| `Warehouse` | `Ops - Inventory` | Read, Write, Create |
| `Supplier` | `Ops - Inventory` | Read |
| `Purchase Order` | `Ops - Inventory` | Read |
| `Purchase Receipt` | `Ops - Inventory` | Read, Write, Create, Submit |
| `Stock Entry` | `Ops - Inventory` | Read, Write, Create, Submit |
| `Stock Reconciliation` | `Ops - Inventory` | Read, Write, Create, Submit |
| `Task` | `Ops - Inventory` | Read, Write, Create |

---

## 7. Accounting and finance permissions

These are needed for invoicing, supplier prepayments, landed cost, and payment collection.

For `Ops - Accounting`:

| DocType | Role | Permissions |
|---|---|---|
| `Supplier` | `Ops - Accounting` | Read |
| `Customer` | `Ops - Accounting` | Read |
| `Warehouse` | `Ops - Accounting` | Read |
| `Purchase Order` | `Ops - Accounting` | Read |
| `Purchase Receipt` | `Ops - Accounting` | Read |
| `Payment Entry` | `Ops - Accounting` | Read, Write, Create, Submit, Cancel, Amend |
| `Purchase Invoice` | `Ops - Accounting` | Read, Write, Create, Submit, Cancel, Amend |
| `Sales Invoice` | `Ops - Accounting` | Read, Write, Create, Submit, Cancel, Amend |
| `Landed Cost Voucher` | `Ops - Accounting` | Read, Write, Create, Submit, Cancel, Amend |
| `Task` | `Ops - Accounting` | Read, Write, Create |

For `Ops - Finance`:

| DocType | Role | Permissions |
|---|---|---|
| `Payment Entry` | `Ops - Finance` | Read, Write, Create, Submit, Cancel, Amend |
| `Sales Invoice` | `Ops - Finance` | Read |
| `Task` | `Ops - Finance` | Read, Write, Create |

---

## 8. Director permissions

These are needed for approval testing.

| DocType | Role | Permissions |
|---|---|---|
| `Task` | `Ops - Directors` | Read, Write, Create |
| `Supplier` | `Ops - Directors` | Read |
| `Customer` | `Ops - Directors` | Read |
| `Item` | `Ops - Directors` | Read, Write, Create |
| `Purchase Order` | `Ops - Directors` | Read |
| `Sales Order` | `Ops - Directors` | Read |
| `Sales Invoice` | `Ops - Directors` | Read |

---

## 9. Order, delivery, and returns permissions

For `Ops - Order Accepting`:

| DocType | Role | Permissions |
|---|---|---|
| `Customer` | `Ops - Order Accepting` | Read, Write, Create |
| `Contact` | `Ops - Order Accepting` | Read, Write, Create |
| `Address` | `Ops - Order Accepting` | Read, Write, Create |
| `Item` | `Ops - Order Accepting` | Read |
| `Warehouse` | `Ops - Order Accepting` | Read |
| `Sales Order` | `Ops - Order Accepting` | Read, Write, Create, Submit |
| `Task` | `Ops - Order Accepting` | Read, Write, Create |

For `Ops - Order Creating`:

| DocType | Role | Permissions |
|---|---|---|
| `Sales Order` | `Ops - Order Creating` | Read, Write, Create, Submit |
| `Task` | `Ops - Order Creating` | Read, Write, Create |

For `Ops - Delivery`:

| DocType | Role | Permissions |
|---|---|---|
| `Delivery Note` | `Ops - Delivery` | Read, Write |
| `Stock Entry` | `Ops - Delivery` | Read only |
| `Task` | `Ops - Delivery` | Read, Write, Create |

For `Ops - Returns`:

| DocType | Role | Permissions |
|---|---|---|
| `Stock Entry` | `Ops - Returns` | Read, Write, Create, Submit |
| `Delivery Note` | `Ops - Returns` | Read |
| `Task` | `Ops - Returns` | Read, Write, Create |

For `Delivery Driver`:

| DocType | Role | Permissions |
|---|---|---|
| `Task` | `Delivery Driver` | Read, Write |

Drivers should not have create/submit access to stock, invoice, payment, or purchase documents.

---

## 10. Supplier master data to create or confirm

Search for `Supplier Group` and open the **Supplier Group** list.

Confirm these supplier groups exist:

- `Distributor`
- `Local`
- `Raw Material`
- `Services`
- `Pharmaceutical`
- `Hardware`
- `Electrical`

Search for `Payment Term` and open the **Payment Term** list.

Confirm these payment terms exist:

- `Prepayment 100%`
- `Prepayment 50%`
- `Balance 50%`

Search for `Payment Terms Template` and open the **Payment Terms Template** list.

Confirm these templates exist:

| Template | Expected terms |
|---|---|
| `Prepayment 100%` | 100% payment in advance |
| `Prepayment 50/50` | 50% advance and 50% balance |

Search for `Supplier` and open the **Supplier** list.

Confirm these suppliers exist and are configured:

| Supplier | Supplier Group | Default Currency | Default Payment Terms Template |
|---|---|---|---|
| `ZMD` | `Distributor` | `USD` | `Prepayment 100%` |
| `CHUNLI` | `Distributor` | `USD` | `Prepayment 100%` |

---

## 11. Item and price setup to check before sales/purchase tests

Search for `Item` and open the **Item** list.

For items used in tests, confirm:

- item is not disabled
- item has correct item group
- item has correct stock UOM
- item has supplier information if purchasing test requires supplier-specific items
- `hs_code` is filled for import items if landed cost/import duty test uses them
- `import_tax_rate` is filled for import items if landed cost/import duty test uses them

Search for `Item Price` and open the **Item Price** list.

For sales tests, confirm test items have selling prices.

For purchase tests, confirm test items have buying prices if the purchase flow needs prices to auto-fill.

---

## 12. Task setup to check

Search for `Task` and open the **Task** list.

Confirm `Task` has the needed custom fields used by the manuals and governance scripts:

- `task_kind`
- `task_access_policy`
- `completed_at`

Search for `Task Access Policy` and open the **Task Access Policy** list.

Confirm policies exist for the operational task kinds used in testing, including:

- `Order entry`
- `Pack / prepare items`
- `Dispatch picking / hand-off`
- `Delivery`
- `Pickup Returns`
- `Return drop-off at warehouse`
- `Returns processing / verification`
- `Invoice preparation / create invoice`
- `Debt Collection`
- `Distribute Payment`
- `Discount Approval`
- `Purchase Approval`
- `Write-off Approval`

If task visibility is restricted by User Permissions, create matching `User Permission` records for each example user.

---

## 13. After changing permissions

After you change roles or permissions:

1. Save the Role Permission Manager changes.
2. Log out from the example user.
3. Log back in as the example user.
4. Search for the DocType by exact name.
5. Test whether the list opens.
6. Test whether **New** appears only where the role should create records.

If a DocType still does not appear in search:

- try a private/incognito browser window
- log out and log back in again
- as System Manager, clear cache if available
- confirm the user is a `System User`, not a restricted website-only user
- confirm the role is assigned directly to the user
- confirm the permission row is on permission level `0`

---

## 14. Fast smoke test order

Use this order after setup:

1. Log in as `purchasing.team@example.com` and search for `Supplier`.
2. Open `Supplier` and confirm `ZMD` and `CHUNLI` are visible.
3. Search for `Purchase Order` and confirm **New** is available.
4. Log in as `inventory.team@example.com` and search for `Item` and `Purchase Receipt`.
5. Log in as `accounting.team@example.com` and search for `Payment Entry`, `Purchase Invoice`, and `Landed Cost Voucher`.
6. Log in as `directors.team@example.com` and search for `Task`.
7. Log in as `order.team@example.com` and search for `Sales Order`.
8. Log in as `delivery.team@example.com` and search for `Task` and `Delivery Note`.
9. Log in as `returns.team@example.com` and search for `Stock Entry`.
10. Log in as `driver.01@example.com` and confirm the driver can open `Task` but cannot create stock or accounting records.

---

## 15. Important safety rule

Do not give `System Manager` to normal example users just to bypass a test blocker.

If a normal example user cannot open a screen, fix the role permission or role assignment instead. This keeps the test close to real future users.

---

## 16. Exact role packages to assign from the available ERPNext role list

Use this section when you are inside a **User** record and selecting roles from the roles table.

These packages use the actual roles available in this ERPNext site.

### 16.1 Purchasing test user

User:

- `purchasing.team@example.com`

Assign:

- `Ops - Purchasing`
- `Ops - Purchasing Lead`
- `Purchase User`
- `Purchase Manager`
- `Purchase Master Manager`
- `Item Manager`

Why these are needed:

- `Ops - Purchasing` is the custom operational role used by the manuals.
- `Ops - Purchasing Lead` gives stronger purchasing-test permissions where lead approval or price maintenance is needed.
- `Purchase User` helps ERPNext show purchasing screens and lists.
- `Purchase Manager` helps with purchasing document operations.
- `Purchase Master Manager` helps with supplier and purchasing master records.
- `Item Manager` helps purchasing open item master information and item-supplier details.

Expected screens after login:

- Search for `Supplier` and open the **Supplier** list.
- Search for `Purchase Order` and open the **Purchase Order** list.
- Search for `Payment Terms Template` and open the **Payment Terms Template** list.
- Search for `Item` and open the **Item** list.

Do not assign:

- `Accounts Manager`
- `Accounts User`
- `Stock Manager`
- `System Manager`

### 16.2 Inventory test user

User:

- `inventory.team@example.com`

Assign:

- `Ops - Inventory`
- `Stock User`
- `Stock Manager`
- `Item Manager`
- `Purchase User`

Why these are needed:

- `Ops - Inventory` is the custom warehouse role used by the manuals.
- `Stock User` opens stock and warehouse screens.
- `Stock Manager` allows stock document creation/submission for testing.
- `Item Manager` allows item setup and item master corrections.
- `Purchase User` allows reading purchase documents such as `Purchase Order` during receiving.

Expected screens after login:

- Search for `Item` and open the **Item** list.
- Search for `Purchase Receipt` and open the **Purchase Receipt** list.
- Search for `Stock Entry` and open the **Stock Entry** list.
- Search for `Stock Reconciliation` and open the **Stock Reconciliation** list.
- Search for `Warehouse` and open the **Warehouse** list.

Do not assign:

- `Accounts Manager`
- `Sales Manager`
- `System Manager`

### 16.3 Accounting test user

User:

- `accounting.team@example.com`

Assign:

- `Ops - Accounting`
- `Accounts User`
- `Accounts Manager`
- `Purchase User`
- `Sales User`
- `Stock User`

Why these are needed:

- `Ops - Accounting` is the custom accounting workflow role.
- `Accounts User` opens accounting documents and ledgers.
- `Accounts Manager` allows submitting/cancelling/amending accounting documents during testing.
- `Purchase User` allows reading purchase documents behind supplier invoices.
- `Sales User` allows reading sales documents behind customer invoices.
- `Stock User` allows reading warehouse/stock context needed by invoices and landed cost.

Expected screens after login:

- Search for `Payment Entry` and open the **Payment Entry** list.
- Search for `Purchase Invoice` and open the **Purchase Invoice** list.
- Search for `Sales Invoice` and open the **Sales Invoice** list.
- Search for `Landed Cost Voucher` and open the **Landed Cost Voucher** list.
- Search for `Supplier` and open the **Supplier** list as read-only.
- Search for `Customer` and open the **Customer** list as read-only.

Do not assign:

- `System Manager`
- `Stock Manager`
- `Purchase Manager`
- `Sales Manager`

### 16.4 Directors test user

User:

- `directors.team@example.com`

Assign:

- `Ops - Directors`
- `Accounts User`
- `Purchase User`
- `Sales User`
- `Stock User`
- `Projects User`
- `Report Manager`
- `Dashboard Manager`

Why these are needed:

- `Ops - Directors` is the custom approval/escalation role.
- `Accounts User`, `Purchase User`, `Sales User`, and `Stock User` give broad read visibility.
- `Projects User` helps if tasks/projects are linked.
- `Report Manager` and `Dashboard Manager` help directors review operational reporting screens.

Expected screens after login:

- Search for `Task` and open the **Task** list.
- Search for `Purchase Order` and open the **Purchase Order** list.
- Search for `Sales Order` and open the **Sales Order** list.
- Search for `Sales Invoice` and open the **Sales Invoice** list.
- Search for `Item` and open the **Item** list.

Optional during setup/testing only:

- `Item Manager`

Do not assign by default:

- `System Manager`

### 16.5 Order accepting test user

User:

- `order.team@example.com`

Assign:

- `Ops - Order Accepting`
- `Sales User`
- `Sales Manager`

Why these are needed:

- `Ops - Order Accepting` is the custom order-entry role.
- `Sales User` opens sales screens.
- `Sales Manager` helps create/edit customers and sales orders during testing.

Expected screens after login:

- Search for `Customer` and open the **Customer** list.
- Search for `Contact` and open the **Contact** list.
- Search for `Address` and open the **Address** list.
- Search for `Sales Order` and open the **Sales Order** list.
- Search for `Task` and open the **Task** list.

Do not assign:

- `Accounts Manager`
- `Stock Manager`
- `Purchase Manager`
- `System Manager`

### 16.6 Order creating test user

User:

- `order.creation.team@example.com`

Assign:

- `Ops - Order Creating`
- `Sales User`
- `Sales Manager`
- `Stock User`

Why these are needed:

- `Ops - Order Creating` is used for converting accepted work into operational sales/order documents.
- `Sales User` and `Sales Manager` allow sales document work.
- `Stock User` allows item/warehouse availability visibility.

Expected screens after login:

- Search for `Sales Order` and open the **Sales Order** list.
- Search for `Item` and open the **Item** list.
- Search for `Warehouse` and open the **Warehouse** list.
- Search for `Task` and open the **Task** list.

Do not assign:

- `Accounts Manager`
- `Purchase Manager`
- `System Manager`

### 16.7 Delivery coordinator test user

User:

- `delivery.team@example.com`

Assign:

- `Ops - Delivery`
- `Delivery User`
- `Delivery Manager`
- `Stock User`

Why these are needed:

- `Ops - Delivery` is the custom delivery coordination role.
- `Delivery User` opens delivery screens.
- `Delivery Manager` helps coordinate/edit delivery documents during testing.
- `Stock User` gives warehouse/item visibility without stock-management power.

Expected screens after login:

- Search for `Task` and open the **Task** list.
- Search for `Delivery Note` and open the **Delivery Note** list.
- Search for `Stock Entry` and confirm read-only access if needed.

Do not assign:

- `Accounts Manager`
- `Stock Manager`
- `System Manager`

### 16.8 Returns test user

User:

- `returns.team@example.com`

Assign:

- `Ops - Returns`
- `Stock User`
- `Stock Manager`
- `Delivery User`

Why these are needed:

- `Ops - Returns` is the custom returns role.
- `Stock User` opens stock screens.
- `Stock Manager` allows stock corrections/returns movement during testing.
- `Delivery User` helps read delivery documents connected to returns.

Expected screens after login:

- Search for `Task` and open the **Task** list.
- Search for `Stock Entry` and open the **Stock Entry** list.
- Search for `Delivery Note` and open the **Delivery Note** list.

Do not assign:

- `Accounts Manager`
- `System Manager`

### 16.9 Driver test user

User:

- `driver.01@example.com`

Assign:

- `Delivery Driver`
- `Delivery User`

Why these are needed:

- `Delivery Driver` is the restricted custom driver role.
- `Delivery User` helps open delivery-related screens if ERPNext requires the standard delivery role.

Expected screens after login:

- Search for `Task` and open the **Task** list.

The driver should not be able to create:

- `Stock Entry`
- `Sales Invoice`
- `Payment Entry`
- `Purchase Order`
- `Purchase Receipt`

Do not assign:

- `Stock User`
- `Stock Manager`
- `Accounts User`
- `Accounts Manager`
- `Purchase User`
- `Purchase Manager`
- `Sales User`
- `Sales Manager`
- `System Manager`

### 16.10 Finance test user

User:

- `finance.team@example.com`

Assign:

- `Ops - Finance`
- `Accounts User`
- `Accounts Manager`

Why these are needed:

- `Ops - Finance` is the custom collections/payment role.
- `Accounts User` opens accounting documents.
- `Accounts Manager` allows creating/submitting payment entries during testing.

Expected screens after login:

- Search for `Payment Entry` and open the **Payment Entry** list.
- Search for `Sales Invoice` and open the **Sales Invoice** list.
- Search for `Task` and open the **Task** list.

Do not assign:

- `Stock Manager`
- `Purchase Manager`
- `Sales Manager`
- `System Manager`

### 16.11 Your own System Manager account

Use your own real account for setup work.

Assign to yourself:

- `System Manager`
- `Script Manager`
- `Workspace Manage`
- `Report Manager`
- `Dashboard Manager`
- `Accounts Manager`
- `Sales Manager`
- `Purchase Manager`
- `Stock Manager`
- `Item Manager`
- `Projects Manager`

Why:

- This account is for configuration, setup, fixing permissions, scripts, dashboards, reports, workspaces, master data, and testing admin-only changes.

Do not use this account to prove that normal users can do their work. After setup, always log in as the example user being tested.

---

## 17. Permission checkbox meaning in Role Permission Manager

When you use `Role Permission Manager`, these checkboxes mean:

- **Read:** user can open the list and view records.
- **Write:** user can edit existing draft or allowed records.
- **Create:** user can click **New** and create records.
- **Submit:** user can submit submittable documents such as `Purchase Order`, `Purchase Receipt`, `Payment Entry`, `Sales Invoice`, or `Stock Entry`.
- **Cancel:** user can cancel submitted documents.
- **Amend:** user can create an amended document after cancellation.
- **Report:** user can use reports related to that DocType.
- **Export:** user can export list data.
- **Print:** user can print documents.
- **Email:** user can email documents.

Use these rules:

- For normal master setup roles, use **Read, Write, Create**.
- For transaction users who finalize documents, add **Submit**.
- For accounting managers, add **Cancel** and **Amend** only where corrections are part of the test.
- For drivers, do not give **Create** or **Submit** on stock/accounting/purchase/sales documents.

---

## 18. If a user still cannot find a DocType

Use this exact troubleshooting order.

### 18.1 Check role assignment

1. Log in as System Manager.
2. Search for `User` and open the **User** list.
3. Open the example user.
4. Confirm the required roles are in the **Roles** table.
5. Save the user.

### 18.2 Check the user type

Inside the **User** record:

- **Enabled** must be checked.
- **User Type** should normally be `System User`.

If the user is a website-only user, ERPNext desk screens may not appear correctly.

### 18.3 Check Role Permission Manager

1. Search for `Role Permission Manager` and open the **Role Permission Manager** tool.
2. Select the missing DocType, for example `Supplier`.
3. Confirm the user's role has **Read** checked.
4. If the user must create records, confirm **Create** is checked.
5. If the user must edit records, confirm **Write** is checked.
6. Save.

### 18.4 Log out and log back in

Permission changes may not apply to an already-open user session.

After changing permissions:

1. Log out from the example user.
2. Close that browser tab.
3. Open a new tab or private/incognito window.
4. Log in again as the example user.
5. Search for the exact DocType name.

### 18.5 Test direct search names

Search exact names:

- `Supplier`
- `Purchase Order`
- `Purchase Receipt`
- `Payment Entry`
- `Purchase Invoice`
- `Sales Order`
- `Sales Invoice`
- `Delivery Note`
- `Stock Entry`
- `Task`
- `Item`

If the user can open the direct URL/list but it does not appear in a workspace, the issue is workspace visibility, not DocType permission.

---

## 19. Minimum setup order before testing all manuals

Do setup in this order:

1. Log in with your own System Manager account.
2. Confirm all roles in section 3 exist.
3. Assign role packages from section 16 to all example users.
4. Configure Role Permission Manager from sections 5 through 9.
5. Confirm supplier groups, payment terms, and suppliers from section 10.
6. Confirm item and item price readiness from section 11.
7. Confirm task fields and task access policies from section 12.
8. Log out from System Manager.
9. Log in as each example user and run the smoke tests from section 14.

Do not start detailed manual testing until the smoke tests pass.

---

## 20. What success looks like

The setup is ready when these checks pass:

| Test user | Must be able to search/open | Must be able to create |
|---|---|---|
| `purchasing.team@example.com` | `Supplier`, `Purchase Order`, `Item`, `Payment Terms Template` | `Supplier`, `Purchase Order` |
| `inventory.team@example.com` | `Item`, `Purchase Receipt`, `Stock Entry`, `Warehouse` | `Item`, `Purchase Receipt`, `Stock Entry` |
| `accounting.team@example.com` | `Payment Entry`, `Purchase Invoice`, `Sales Invoice`, `Landed Cost Voucher` | `Payment Entry`, `Purchase Invoice`, `Sales Invoice`, `Landed Cost Voucher` |
| `directors.team@example.com` | `Task`, `Purchase Order`, `Sales Order`, `Sales Invoice` | approval/edit tasks only |
| `order.team@example.com` | `Customer`, `Sales Order`, `Item`, `Task` | `Customer`, `Sales Order` |
| `delivery.team@example.com` | `Task`, `Delivery Note` | delivery coordination updates only |
| `returns.team@example.com` | `Task`, `Stock Entry`, `Delivery Note` | `Stock Entry` |
| `driver.01@example.com` | `Task` | no stock/accounting/purchase/sales documents |
| `finance.team@example.com` | `Payment Entry`, `Sales Invoice`, `Task` | `Payment Entry` |

If these checks pass, the manuals are much less likely to fail because of missing roles or missing master setup.
