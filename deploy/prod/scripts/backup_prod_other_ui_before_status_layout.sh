#!/usr/bin/env bash
set -euo pipefail
STAMP="$(date +%Y%m%d_%H%M%S)"
DIR="/root/prod_other_ui_backup_$STAMP"
mkdir -p "$DIR"

docker exec -i frappe-db-1 mariadb -uroot -pfd88f0ff7 -N _f98256a6d2bdfda2 <<'SQL' > "$DIR/Task-Other_UI_Cleanup.script.txt"
select script from `tabClient Script` where name='Task-Other UI Cleanup';
SQL

docker exec -i frappe-db-1 mariadb -uroot -pfd88f0ff7 -N _f98256a6d2bdfda2 <<'SQL' > "$DIR/Task-Other_UI_Cleanup.row.tsv"
select name, dt, enabled, sha2(coalesce(script,''),256), modified from `tabClient Script` where name='Task-Other UI Cleanup';
SQL

echo "BACKUP_DIR=$DIR"
cat "$DIR/Task-Other_UI_Cleanup.row.tsv"
