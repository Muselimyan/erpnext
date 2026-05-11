# ERPNext Deployment Scripts

All server-side scripts live in `deploy/`. They run inside the `frappe-backend-1` Docker container on VPS `161.97.83.156`.

## How to run a script

1. Upload the script to the server:
   ```powershell
   scp -i "$env:USERPROFILE\.ssh\vps_erpnext2" deploy\<script>.py root@161.97.83.156:/tmp/<script>.py
   ssh -i "$env:USERPROFILE\.ssh\vps_erpnext2" root@161.97.83.156 "docker cp /tmp/<script>.py frappe-backend-1:/home/frappe/<script>.py"
   ```
2. Edit `deploy/run_step1.sh` to point `exec(open(...))` at your script.
3. Upload and run:
   ```powershell
   scp ... run_step1.sh root@161.97.83.156:/tmp/run_step1.sh
   ssh ... "docker cp /tmp/run_step1.sh frappe-backend-1:/home/frappe/run_step1.sh && docker exec frappe-backend-1 bash /home/frappe/run_step1.sh 2>&1"
   ```

---

## Reusable Scripts

### `deploy/run_step1.sh`
Shell wrapper that initialises Frappe site and executes any Python script inside the container. Change the `exec(open(...))` line to point at the desired script.

---

### `deploy/deploy_customers.py`
**Full customer rebuild.** Drops unique constraint on `client_code`, deletes all Sales Orders / Invoices / Payment Entries / Customers, then recreates customers from `/home/frappe/customers_preview.csv`.

Input file: `deploy/data/customers-preview.csv` (upload to `/home/frappe/customers_preview.csv` first).

---

### `deploy/doc-resync-rebuild-warehouses-v2.py`
**Full warehouse tree rebuild.** Deletes all H-type and D-type warehouses under "Clients - Inmed", then recreates them from `/home/frappe/wh.txt`.

- Hospital format in wh.txt: `Hxxx - Hospital Name`
- Doctor format: `Dxxx - Doctor Name - Hospital Name`
- Created names: `Hxxx — Hospital Name - Inmed` / `Dxxx — Doctor Name — Hospital Name - Inmed`

Input file: `deploy/data/wh.txt` (upload to `/home/frappe/wh.txt` first).

---

### `deploy/export-warehouses.py`
Exports the full `tabWarehouse` table to `/tmp/warehouses.csv` (UTF-8 BOM). Download with `scp` afterwards.

---

### `deploy/generate_customers_preview.py`
Reads the live warehouse tree from ERPNext and generates a `customers-preview.csv` scaffold. Useful to regenerate the CSV after a warehouse rebuild.

---

### `deploy/deploy_so_client_script.py`
Creates/updates the **Sales Order** client script `SO-customer-autofill`. When a customer is selected on a SO, auto-fills `hospital` and `doctor_name`:
- Hospital customer → `hospital` = the customer itself
- Doctor customer → `hospital` + `doctor_name` from the customer record

---

### `deploy/doc-resync-step3-customer-fields.ps1`
Adds `hospital` (Link → Customer) and `doctor_name` (Data) custom fields to the Customer DocType via the ERPNext REST API. Run with `-Mode Deploy`.

---

### `deploy/export.ps1`
Stores API credentials (`BaseUrl`, `ApiKey`, `ApiSec`) and shared helper functions used by all PowerShell deploy scripts.

---

### `deploy/doc07a-deploy.ps1` … `doc13a-deploy.ps1`
Schema deployment scripts for each configuration batch (custom fields, roles, permissions, DocTypes, client scripts, etc.). Run in order when deploying to a fresh site.

---

## One-time / debug scripts (deploy/ — not for reuse)
| Script | Purpose |
|--------|---------|
| `doc-resync-fix-h050-*.py` | Fixed H050 warehouse name encoding |
| `doc-resync-fixes2.py` | Incremental warehouse name fixes |
| `doc-resync-step1-*.py` | Early warehouse manipulation helpers |
| `dump_h050_codepoints.py` | Debug: print Unicode code points |
| `query_h050.py` | Debug: query H050 record |
| `delete_customers.py` | Standalone customer deletion (now included in `deploy_customers.py`) |
