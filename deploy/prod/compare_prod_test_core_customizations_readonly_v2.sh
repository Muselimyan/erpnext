#!/usr/bin/env bash
set -euo pipefail
TMP="/tmp/prod_test_core_compare_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$TMP"
PROD_DB="_f98256a6d2bdfda2"
TEST_DB="_b9d33ed61d78a9f2"
PROD_PW="fd88f0ff7"
TEST_PW="tSt7f92k1QzR"
query_prod() { docker exec -i frappe-db-1 mariadb -uroot -p"$PROD_PW" -N "$PROD_DB"; }
query_test() { docker exec -i frappe-test-db-1 mariadb -uroot -p"$TEST_PW" -N "$TEST_DB"; }
compare_query() {
  label="$1"
  sql="$2"
  safe=$(echo "$label" | tr ' /' '__')
  echo "$sql" | query_prod > "$TMP/prod_$safe.tsv"
  echo "$sql" | query_test > "$TMP/test_$safe.tsv"
  echo "=== $label ==="
  echo "prod_count=$(wc -l < "$TMP/prod_$safe.tsv") test_count=$(wc -l < "$TMP/test_$safe.tsv")"
  echo "prod_hash=$(sha256sum "$TMP/prod_$safe.tsv" | cut -d' ' -f1)"
  echo "test_hash=$(sha256sum "$TMP/test_$safe.tsv" | cut -d' ' -f1)"
  if cmp -s "$TMP/prod_$safe.tsv" "$TMP/test_$safe.tsv"; then
    echo "match=yes"
  else
    echo "match=no"
    diff -u "$TMP/test_$safe.tsv" "$TMP/prod_$safe.tsv" | sed -n '1,140p' || true
  fi
  echo
}
compare_query "Client Script" "select name, dt, enabled, sha2(coalesce(script,''),256) from \`tabClient Script\` order by name;"
compare_query "Server Script" "select name, script_type, reference_doctype, disabled, sha2(coalesce(script,''),256) from \`tabServer Script\` order by name;"
compare_query "Task Client Script" "select name, enabled, sha2(coalesce(script,''),256) from \`tabClient Script\` where dt='Task' order by name;"
compare_query "Task Server Script" "select name, script_type, reference_doctype, disabled, sha2(coalesce(script,''),256) from \`tabServer Script\` where reference_doctype='Task' or script like '%Task%' order by name;"
compare_query "Task Custom Field" "select name, fieldname, fieldtype, label, insert_after, hidden, read_only, reqd, idx from \`tabCustom Field\` where dt='Task' order by name;"
compare_query "Custom Field All" "select name, dt, fieldname, fieldtype, label, insert_after, hidden, read_only, reqd, idx from \`tabCustom Field\` order by name;"
compare_query "Property Setter" "select name, doc_type, field_name, property, property_type, value from \`tabProperty Setter\` order by name;"
compare_query "Task Access Policy" "select name, task_kind, disabled from \`tabTask Access Policy\` order by name;"
echo "TMP=$TMP"
