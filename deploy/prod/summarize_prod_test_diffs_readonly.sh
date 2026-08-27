#!/usr/bin/env bash
set -euo pipefail
TMP="/tmp/prod_test_diff_details_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$TMP"

get_prod_client() { docker exec -i frappe-db-1 mariadb -uroot -pfd88f0ff7 -N _f98256a6d2bdfda2; }
get_test_client() { docker exec -i frappe-test-db-1 mariadb -uroot -ptSt7f92k1QzR -N _b9d33ed61d78a9f2; }

for kind in client server; do
  for name in "Task-Account Details UI Cleanup" "Task-Other UI Cleanup" "Task-after-save-other-processing" "Task-Other Entry Default Subject" "Telegram Task Assignment Notification" "Telegram Task Status Update"; do
    table="tabClient Script"
    [ "$kind" = server ] && table="tabServer Script"
    echo "select script from \`$table\` where name='$name';" | get_prod_client | sed 's/\\n/\n/g' > "$TMP/prod_${kind}_${name// /_}.txt"
    echo "select script from \`$table\` where name='$name';" | get_test_client | sed 's/\\n/\n/g' > "$TMP/test_${kind}_${name// /_}.txt"
  done
done

echo "=== Account Details UI exact diff around next task assign ==="
diff -u "$TMP/test_client_Task-Account_Details_UI_Cleanup.txt" "$TMP/prod_client_Task-Account_Details_UI_Cleanup.txt" | grep -C 8 -E 'custom_next_task_assign_to|nextAssignControl|account details: processing' || true

echo
for f in "$TMP"/prod_client_Task-Other_UI_Cleanup.txt "$TMP"/prod_server_Task-after-save-other-processing.txt "$TMP"/prod_server_Task-Other_Entry_Default_Subject.txt; do
  echo "=== $(basename "$f") first 120 lines ==="
  sed -n '1,120p' "$f"
  echo
done

echo "=== Telegram URL/token relevant diff ==="
diff -u "$TMP/test_server_Telegram_Task_Assignment_Notification.txt" "$TMP/prod_server_Telegram_Task_Assignment_Notification.txt" | grep -C 4 -E 'raw_token|get_password|base_url|task_url|test.erpnext|erpnext.am' || true
diff -u "$TMP/test_server_Telegram_Task_Status_Update.txt" "$TMP/prod_server_Telegram_Task_Status_Update.txt" | grep -C 4 -E 'raw_token|get_password|base_url|task_url|test.erpnext|erpnext.am' || true

echo "TMP=$TMP"
