#!/usr/bin/env bash
set -euo pipefail

docker exec -i frappe-db-1 mariadb -uroot -pfd88f0ff7 -N <<'SQL' | python3 -c 'import sys; s=sys.stdin.read().replace("\\n","\n"); print("\n".join(f"{i+1}: {line}" for i,line in enumerate(s.splitlines())))'
select script from `_f98256a6d2bdfda2`.`tabClient Script` where name='Task-Account Details UI Cleanup';
SQL
