# ERPNext Deployment Scripts

Server-side scripts live under `deploy/prod/` (targets `https://erpnext.am` / container `frappe-backend-1`) or `deploy/test/` (targets `https://test.erpnext.am` / container `frappe-test-backend-1`) — never directly in `deploy/`. See `@c:\Users\Vahe\CascadeProjects\erpnext\docs\infrastructure-test-vs-prod-environments.md` for the full prod/test split, credentials, and diff procedure. Examples below assume prod; swap the container name and paths for test.

## How to run a script

1. Upload the script to the server:
   ```powershell
   scp -i "$env:USERPROFILE\.ssh\vps_erpnext2" deploy\prod\<script>.py root@161.97.83.156:/tmp/<script>.py
   ssh -i "$env:USERPROFILE\.ssh\vps_erpnext2" root@161.97.83.156 "docker cp /tmp/<script>.py frappe-backend-1:/home/frappe/<script>.py"
   ```
2. Edit `deploy/prod/run_step1.sh` to point `exec(open(...))` at your script.
3. Upload and run:
   ```powershell
   scp ... run_step1.sh root@161.97.83.156:/tmp/run_step1.sh
   ssh ... "docker cp /tmp/run_step1.sh frappe-backend-1:/home/frappe/run_step1.sh && docker exec frappe-backend-1 bash /home/frappe/run_step1.sh 2>&1"
   ```

---

## Reusable Scripts

### `deploy/prod/run_step1.sh`
Shell wrapper that initialises Frappe site and executes any Python script inside the container. Change the `exec(open(...))` line to point at the desired script.

---

### `deploy/prod/deploy_customers.py`
**Full customer rebuild.** Drops unique constraint on `client_code`, deletes all Sales Orders / Invoices / Payment Entries / Customers, then recreates customers from `/home/frappe/customers_preview.csv`.

Input file: `deploy/prod/data/customers-preview.csv` (upload to `/home/frappe/customers_preview.csv` first).

---

### `deploy/prod/doc-resync-rebuild-warehouses-v2.py`
**Full warehouse tree rebuild.** Deletes all H-type and D-type warehouses under "Clients - Inmed", then recreates them from `/home/frappe/wh.txt`.

- Hospital format in wh.txt: `Hxxx - Hospital Name`
- Doctor format: `Dxxx - Doctor Name - Hospital Name`
- Created names: `Hxxx — Hospital Name - Inmed` / `Dxxx — Doctor Name — Hospital Name - Inmed`

Input file: `deploy/prod/data/wh.txt` (upload to `/home/frappe/wh.txt` first).

---

### `deploy/prod/export-warehouses.py`
Exports the full `tabWarehouse` table to `/tmp/warehouses.csv` (UTF-8 BOM). Download with `scp` afterwards.

---

### `deploy/prod/generate_customers_preview.py`
Reads the live warehouse tree from ERPNext and generates a `customers-preview.csv` scaffold. Useful to regenerate the CSV after a warehouse rebuild.

---

### `deploy/prod/deploy_so_client_script.py`
Creates/updates the **Sales Order** client script `SO-customer-autofill`. When a customer is selected on a SO, auto-fills `hospital` and `doctor_name`:
- Hospital customer → `hospital` = the customer itself
- Doctor customer → `hospital` + `doctor_name` from the customer record

---

### `deploy/prod/doc-resync-step3-customer-fields.ps1`
Adds `hospital` (Link → Customer) and `doctor_name` (Data) custom fields to the Customer DocType via the ERPNext REST API. Run with `-Mode Deploy`.

---

### `deploy/prod/export.ps1` / `deploy/test/export.ps1`
Each stores that environment's own API credentials (`BaseUrl`, `ApiKey`, `ApiSec`) and shared helper functions. Most other PowerShell scripts in the same folder read this file (via `$PSScriptRoot`) to get credentials — this is also how they know which environment they target. Can be run standalone to pull a full schema/data snapshot (see `@c:\Users\Vahe\CascadeProjects\erpnext\docs\infrastructure-test-vs-prod-environments.md` §10 for the diff workflow).

---

### `deploy/prod/doc07a-deploy.ps1` … `doc13a-deploy.ps1`
Schema deployment scripts for each configuration batch (custom fields, roles, permissions, DocTypes, client scripts, etc.). Run in order when deploying to a fresh site.

---

## One-time / debug scripts (deploy/prod/ — not for reuse)
| Script | Purpose |
|--------|---------|
| `doc-resync-fix-h050-*.py` | Fixed H050 warehouse name encoding |
| `doc-resync-fixes2.py` | Incremental warehouse name fixes |
| `doc-resync-step1-*.py` | Early warehouse manipulation helpers |
| `dump_h050_codepoints.py` | Debug: print Unicode code points |
| `query_h050.py` | Debug: query H050 record |
| `delete_customers.py` | Standalone customer deletion (now included in `deploy_customers.py`) |
