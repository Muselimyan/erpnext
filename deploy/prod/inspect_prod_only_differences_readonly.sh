#!/usr/bin/env bash
set -euo pipefail

names=(
  "Task-Other UI Cleanup"
  "Task-after-save-other-processing"
  "Task-Other Entry Default Subject"
  "Task-Account Details UI Cleanup"
  "Telegram Task Assignment Notification"
  "Telegram Task Status Update"
)

for n in "${names[@]}"; do
  echo "==================== $n ===================="
  docker exec -i frappe-db-1 mariadb -uroot -pfd88f0ff7 -N _f98256a6d2bdfda2 <<SQL | python3 -c 'import sys; s=sys.stdin.read().replace("\\n","\n"); print("\n".join(f"{i+1}: {line}" for i,line in enumerate(s.splitlines())))'
select coalesce((select script from \`tabClient Script\` where name='$n'), (select script from \`tabServer Script\` where name='$n'));
SQL
  echo
done
