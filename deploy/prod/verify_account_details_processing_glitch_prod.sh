#!/usr/bin/env bash
set -euo pipefail

docker exec -i frappe-db-1 mariadb -uroot -pfd88f0ff7 -N <<'SQL'
select
  name,
  enabled,
  script like '%frm.toggle_display("custom_next_task_assign_to", false);%frm.toggle_display("custom_next_task_assign_to", true);%' as has_conflicting_next_assign_toggle,
  script like '%frm.toggle_display("custom_next_task_assign_to", taskKind !=%account details: processing%);%' as has_stable_processing_toggle,
  script like '%nextAssignControl.hide();%' as delayed_layout_hides_processing
from `_f98256a6d2bdfda2`.`tabClient Script`
where name='Task-Account Details UI Cleanup';
SQL
