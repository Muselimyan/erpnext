#!/usr/bin/env bash
set -euo pipefail

echo "=== TEST Task client scripts with status priority layout ==="
docker exec -i frappe-test-db-1 mariadb -uroot -ptSt7f92k1QzR -N _b9d33ed61d78a9f2 <<'SQL'
select name, sha2(coalesce(script,''),256)
from `tabClient Script`
where dt='Task' and (script like '%Task Status & Priority%' or script like '%Status and Priority%' or script like '%statusControl%' or script like '%priorityControl%')
order by name;
SQL

echo "=== TEST relevant snippets ==="
docker exec -i frappe-test-db-1 mariadb -uroot -ptSt7f92k1QzR -N _b9d33ed61d78a9f2 <<'SQL' | python3 -c 'import sys; s=sys.stdin.read().replace("\\n","\n");
for i,line in enumerate(s.splitlines(),1):
    if any(x in line for x in ["Task Status & Priority", "Status and Priority", "statusControl", "priorityControl", "complete-task-btn", "custom_barcode_section", "section-head"]):
        print(f"{i}: {line}")'
select script from `tabClient Script` where name in ('Task-Product Work Area','Task-Dispatch Packing Usability','Task-Accept Start','Task-Account Details UI Cleanup') order by name;
SQL

echo "=== PROD Other UI current relevant snippets ==="
docker exec -i frappe-db-1 mariadb -uroot -pfd88f0ff7 -N _f98256a6d2bdfda2 <<'SQL' | python3 -c 'import sys; s=sys.stdin.read().replace("\\n","\n");
for i,line in enumerate(s.splitlines(),1):
    if any(x in line for x in ["task_other_force_status_priority_visible", "Status and Priority", "statusControl", "priorityControl", "complete-task-btn", "custom_barcode_section", "section-head", "appendTo(leftColumn)"]):
        print(f"{i}: {line}")'
select script from `tabClient Script` where name='Task-Other UI Cleanup';
SQL
