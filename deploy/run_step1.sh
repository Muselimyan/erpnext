#!/bin/bash
cd /home/frappe/frappe-bench
/home/frappe/frappe-bench/env/bin/python - <<'EOF'
import frappe
frappe.init(site="161.97.83.156", sites_path="/home/frappe/frappe-bench/sites")
frappe.connect()
exec(open("/home/frappe/deploy_so_client_script.py").read())
frappe.destroy()
EOF
