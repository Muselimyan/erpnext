#!/usr/bin/env bash
set -euo pipefail
TMP="/tmp/prod_test_sync_candidates_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$TMP"
PROD_DB="_f98256a6d2bdfda2"
TEST_DB="_b9d33ed61d78a9f2"
PROD_PW="fd88f0ff7"
TEST_PW="tSt7f92k1QzR"
prod() { docker exec -i frappe-db-1 mariadb -uroot -p"$PROD_PW" -N "$PROD_DB"; }
testdb() { docker exec -i frappe-test-db-1 mariadb -uroot -p"$TEST_PW" -N "$TEST_DB"; }
compare() {
  label="$1"; sql="$2"; safe=$(echo "$label" | tr ' /' '__')
  echo "$sql" | prod > "$TMP/prod_$safe.tsv"
  echo "$sql" | testdb > "$TMP/test_$safe.tsv"
  echo "=== $label ==="
  echo "prod_count=$(wc -l < "$TMP/prod_$safe.tsv") test_count=$(wc -l < "$TMP/test_$safe.tsv")"
  if cmp -s "$TMP/prod_$safe.tsv" "$TMP/test_$safe.tsv"; then echo "match=yes"; else echo "match=no"; diff -u "$TMP/test_$safe.tsv" "$TMP/prod_$safe.tsv" | sed -n '1,220p' || true; fi
  echo
}
compare "Client Script All" "select name, dt, enabled, sha2(coalesce(script,''),256) from \`tabClient Script\` order by name;"
compare "Server Script All" "select name, script_type, reference_doctype, disabled, sha2(coalesce(script,''),256) from \`tabServer Script\` order by name;"
compare "Custom Field All" "select name, dt, fieldname, fieldtype, label, insert_after, hidden, read_only, reqd, idx from \`tabCustom Field\` order by name;"
compare "Property Setter All" "select name, doc_type, field_name, property, property_type, value from \`tabProperty Setter\` order by name;"
compare "Workspace All" "select name, title, public, is_hidden, sha2(coalesce(content,''),256) from \`tabWorkspace\` order by name;"
compare "Workflow State All" "select name, style from \`tabWorkflow State\` order by name;"
compare "Role All" "select name, disabled, desk_access from \`tabRole\` order by name;"
compare "Task Type All" "select name from \`tabTask Type\` order by name;"

echo "=== Operational Counts (not copy candidates) ==="
for table in "Task" "ToDo" "Comment" "File" "User" "Employee" "Customer" "Supplier" "Item"; do
  p=$(echo "select count(*) from \`tab$table\`;" | prod)
  t=$(echo "select count(*) from \`tab$table\`;" | testdb)
  echo "$table prod=$p test=$t"
done

echo "TMP=$TMP"
