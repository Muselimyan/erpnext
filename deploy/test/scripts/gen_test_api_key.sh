#!/bin/bash
docker exec frappe-test-backend-1 bench --site test.erpnext.am execute frappe.core.doctype.user.user.generate_keys --kwargs '{"user": "Administrator"}'
docker exec frappe-test-backend-1 bench --site test.erpnext.am execute frappe.client.get_value --kwargs '{"doctype": "User", "filters": "Administrator", "fieldname": "api_key"}'
