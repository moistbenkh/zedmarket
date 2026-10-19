#!/usr/bin/env bash
# app_user can run the order procedures end to end even though it has no INSERT privilege (procedures run with the owner's rights).
# Leaves one test order behind: run build.sh afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
as_app() { MYSQL_PWD="$APP_DB_PASSWORD" my --user=app_user "$DB_NAME" "$@"; }
OID=$(as_app -N -B -e "CALL place_order_rs(1, 1, '[{\"product_id\":1,\"quantity\":1}]')")
echo "app_user placed order #$OID"
as_app -e "CALL pay_order($OID, 'card', 1)"
as_app -t -e "SELECT order_id, status, total_amount FROM orders WHERE order_id = $OID"
my "$DB_NAME" -t -e "SELECT audit_id, table_name, action, changed_by FROM audit_log WHERE record_id = $OID AND table_name = 'orders' ORDER BY audit_id"
echo "The audit rows were written by triggers even though app_user cannot write audit_log."
