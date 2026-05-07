# AI Agent API Access — Layer 1 Setup Guide

Base URL for all requests: `https://erpnext.am`

---

## Step 1: Create a Dedicated User for the AI Agent

1. Log in to ERPNext as Administrator
2. Go to **Settings → User → New**
3. Fill in:
   - **Email**: `ai-agent@internal` (any valid email format, doesn't need to be real)
   - **First Name**: `AI Agent`
   - **Send Welcome Email**: **uncheck** (no inbox to receive it)
4. Scroll to **Roles** section and add:
   - `System Manager` — if the AI needs full access to all DocTypes
   - OR assign specific roles matching what the AI needs to do (see note below)
5. **Save** the user

> **Role note:** `System Manager` is the safest for an AI agent doing setup/scripting work. If you want to restrict it later, assign only the roles it actually uses (e.g. Stock Manager, Accounts Manager, etc.)

---

## Step 2: Generate API Keys

1. Open the user you just created (**Settings → User → AI Agent**)
2. In the top-right menu click **⋮ (kebab menu) → API Access**
   - Or scroll down the user form — there may be a direct **API Access** section
3. Click **Generate Keys**
4. ERPNext will show a one-time popup with:
   - `API Key` (permanent, visible anytime)
   - `API Secret` (shown **once only** — copy it now)
5. Store both values securely. The token format used in requests is:

```
api_key:api_secret
```

Combined as a Bearer token:

```
Authorization: token <api_key>:<api_secret>
```

---

## Step 3: Verify the Token Works

Run this from any machine (PowerShell or curl):

```powershell
# PowerShell
$headers = @{ Authorization = "token YOUR_API_KEY:YOUR_API_SECRET" }
Invoke-RestMethod -Uri "https://erpnext.am/api/method/frappe.auth.get_logged_user" -Headers $headers
```

```bash
# curl (Linux/Mac/WSL)
curl -H "Authorization: token YOUR_API_KEY:YOUR_API_SECRET" \
  https://erpnext.am/api/method/frappe.auth.get_logged_user
```

Expected response:
```json
{ "message": "ai-agent@internal" }
```

If you get a 403 or 401, double-check the user is **Enabled** and the key/secret are correct.

---

## Step 4: Core API Patterns

### List records
```
GET /api/resource/{DocType}
GET /api/resource/Sales Order?limit=20&filters=[["status","=","Draft"]]
```

### Get a single record
```
GET /api/resource/{DocType}/{name}
GET /api/resource/Customer/CUST-00001
```

### Create a record
```
POST /api/resource/{DocType}
Content-Type: application/json

{ "field1": "value1", "field2": "value2" }
```

### Update a record
```
PUT /api/resource/{DocType}/{name}
Content-Type: application/json

{ "field_to_update": "new_value" }
```

### Delete a record
```
DELETE /api/resource/{DocType}/{name}
```

### Call a whitelisted server method
```
POST /api/method/frappe.client.get_list
POST /api/method/erpnext.some.module.method_name
Content-Type: application/json

{ "arg1": "value" }
```

### Run a Query Report
```
GET /api/method/frappe.desk.query_report.run?report_name=Stock Balance&filters={"warehouse":"Main - WH"}
```

---

## Step 5: Create / Manage Server Scripts via API

The AI can deploy Python logic without SSH by creating **Server Script** documents:

```powershell
# PowerShell example — create a Server Script
$headers = @{
    Authorization  = "token YOUR_API_KEY:YOUR_API_SECRET"
    "Content-Type" = "application/json"
}

$body = @{
    doctype       = "Server Script"
    name          = "my-check-script"
    script_type   = "Script API"   # or "DocType Event", "Scheduler Event"
    api_method    = "my_check_script"
    enabled       = 1
    script        = @"
import frappe

def execute():
    data = frappe.db.sql("SELECT name, status FROM `tabSales Order` LIMIT 10", as_dict=True)
    frappe.response['message'] = data
"@
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Method Post `
    -Uri "https://erpnext.am/api/resource/Server Script" `
    -Headers $headers `
    -Body $body
```

Once created, call the script:
```
POST /api/method/my_check_script
```

---

## Step 6: Query the Database Directly (via Server Script)

For complex checks that the REST resource API can't express, create a Script API Server Script that runs raw SQL and returns results. The AI creates the script via API (Step 5), calls it, reads the result, then can delete or update the script.

---

## Step 7: Useful Endpoints Reference

| Purpose | Endpoint |
|---|---|
| Confirm auth | `GET /api/method/frappe.auth.get_logged_user` |
| List DocTypes | `GET /api/resource/DocType` |
| Get field metadata | `GET /api/resource/DocType/{name}` |
| Get a document | `GET /api/resource/{DocType}/{name}` |
| Search/filter | `GET /api/resource/{DocType}?filters=...&fields=...` |
| Submit a document | `POST /api/method/frappe.client.submit` body: `{"doc": {...}}` |
| Cancel a document | `POST /api/method/frappe.client.cancel` body: `{"doctype":"..","name":".."}` |
| Run report | `GET /api/method/frappe.desk.query_report.run?report_name=...` |
| Get stock balance | `GET /api/resource/Bin?filters=[["warehouse","=","Main - WH"]]` |
| List Server Scripts | `GET /api/resource/Server Script` |

---

## Step 8: Security Hardening (Optional but Recommended)

1. **Restrict by IP** — In the user settings, set **Login Allowed From IP** to the AI agent's IP address only
2. **Limit roles** — Once the AI's actual usage is known, remove `System Manager` and assign only the minimum required roles
3. **Rotate keys** — If the secret is ever exposed, go back to **API Access** and regenerate keys (old secret is invalidated immediately)
4. **Audit log** — ERPNext logs all API calls under **Settings → Activity Log** filtered by user `ai-agent@internal`

---

## Quick Test Checklist

- [ ] User created and enabled
- [ ] API key + secret generated and saved
- [ ] `get_logged_user` returns `ai-agent@internal`
- [ ] `GET /api/resource/Customer` returns customer list
- [ ] `GET /api/resource/Item` returns item list
- [ ] Server Script create + call works (Step 5)
