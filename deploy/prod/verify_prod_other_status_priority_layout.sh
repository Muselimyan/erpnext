#!/usr/bin/env bash
set -euo pipefail

echo "=== Prod Other UI row ==="
docker exec -i frappe-db-1 mariadb -uroot -pfd88f0ff7 -N _f98256a6d2bdfda2 <<'SQL'
select name, enabled, sha2(coalesce(script,''),256), modified
from `tabClient Script`
where name='Task-Other UI Cleanup';
SQL

echo "=== Layout markers ==="
docker exec -i frappe-db-1 mariadb -uroot -pfd88f0ff7 -N _f98256a6d2bdfda2 <<'SQL'
select
  script like '%sectionHead.text(''Task Status & Priority'')%' as has_test_like_label,
  script like '%max-width'':''640px%' as has_left_column_width,
  script like '%if (index > 0) $(this).hide();%' as hides_extra_columns,
  script like '%data-other-status-left%' as has_other_status_marker
from `tabClient Script`
where name='Task-Other UI Cleanup';
SQL
