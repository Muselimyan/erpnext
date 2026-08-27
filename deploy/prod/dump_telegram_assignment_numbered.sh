#!/usr/bin/env bash
set -euo pipefail

for env in prod test; do
  if [ "$env" = prod ]; then
    container=frappe-db-1
    pw=fd88f0ff7
    db=_f98256a6d2bdfda2
  else
    container=frappe-test-db-1
    pw=tSt7f92k1QzR
    db=_b9d33ed61d78a9f2
  fi
  echo "=== $env Telegram Task Assignment Notification ==="
  docker exec -i "$container" mariadb -uroot -p"$pw" -N <<SQL | python3 -c 'import sys; s=sys.stdin.read().replace("\\n","\n"); print("\n".join(f"{i+1}: {line}" for i,line in enumerate(s.splitlines())))'
select script from \`$db\`.\`tabServer Script\` where name='Telegram Task Assignment Notification';
SQL
done
