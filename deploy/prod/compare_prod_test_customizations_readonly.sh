#!/usr/bin/env bash
set -euo pipefail
TMP="/tmp/prod_test_custom_compare_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$TMP"

PROD_DB="_f98256a6d2bdfda2"
TEST_DB="_b9d33ed61d78a9f2"
PROD_PW="fd88f0ff7"
TEST_PW="tSt7f92k1QzR"

query_prod() { docker exec -i frappe-db-1 mariadb -uroot -p"$PROD_PW" -N "$PROD_DB"; }
query_test() { docker exec -i frappe-test-db-1 mariadb -uroot -p"$TEST_PW" -N "$TEST_DB"; }

for table in "Client Script" "Server Script" "Custom Field" "Property Setter" "Workspace" "Report"; do
  safe=$(echo "$table" | tr ' ' '_')
  case "$table" in
    "Client Script") cols="name, dt, enabled, sha2(coalesce(script,''),256)" ;;
    "Server Script") cols="name, script_type, reference_doctype, disabled, sha2(coalesce(script,''),256)" ;;
    "Custom Field") cols="name, dt, fieldname, fieldtype, label, insert_after, hidden, read_only, reqd, in_list_view, idx" ;;
    "Property Setter") cols="name, doc_type, field_name, property, property_type, value" ;;
    "Workspace") cols="name, title, public, is_hidden, sha2(coalesce(content,''),256)" ;;
    "Report") cols="name, ref_doctype, report_type, is_standard, disabled, sha2(coalesce(json,''),256), sha2(coalesce(query,''),256)" ;;
  esac
  echo "select $cols from \`tab$table\` order by name;" | query_prod > "$TMP/prod_$safe.tsv"
  echo "select $cols from \`tab$table\` order by name;" | query_test > "$TMP/test_$safe.tsv"
  echo "=== $table SUMMARY ==="
  echo "prod_count=$(wc -l < "$TMP/prod_$safe.tsv") test_count=$(wc -l < "$TMP/test_$safe.tsv")"
  echo "prod_hash=$(sha256sum "$TMP/prod_$safe.tsv" | cut -d' ' -f1)"
  echo "test_hash=$(sha256sum "$TMP/test_$safe.tsv" | cut -d' ' -f1)"
  if cmp -s "$TMP/prod_$safe.tsv" "$TMP/test_$safe.tsv"; then
    echo "match=yes"
  else
    echo "match=no"
    echo "--- differing rows (first 80 lines) ---"
    diff -u "$TMP/test_$safe.tsv" "$TMP/prod_$safe.tsv" | sed -n '1,80p'
  fi
  echo
done

cat > "$TMP/task_related.sql" <<'SQL'
select 'Task_Client', name, enabled, sha2(coalesce(script,''),256) from `tabClient Script` where dt='Task' order by name;
select 'Task_Server', name, script_type, reference_doctype, disabled, sha2(coalesce(script,''),256) from `tabServer Script` where reference_doctype='Task' or script like '%Task%' order by name;
select 'Task_Custom_Field', name, fieldname, fieldtype, label, hidden, read_only, reqd, idx from `tabCustom Field` where dt='Task' order by name;
SQL
query_prod < "$TMP/task_related.sql" > "$TMP/prod_task_related.tsv"
query_test < "$TMP/task_related.sql" > "$TMP/test_task_related.tsv"
echo "=== TASK RELATED SUMMARY ==="
echo "prod_hash=$(sha256sum "$TMP/prod_task_related.tsv" | cut -d' ' -f1)"
echo "test_hash=$(sha256sum "$TMP/test_task_related.tsv" | cut -d' ' -f1)"
if cmp -s "$TMP/prod_task_related.tsv" "$TMP/test_task_related.tsv"; then
  echo "match=yes"
else
  echo "match=no"
  diff -u "$TMP/test_task_related.tsv" "$TMP/prod_task_related.tsv" | sed -n '1,160p'
fi

echo "TMP=$TMP"
