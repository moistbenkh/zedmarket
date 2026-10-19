#!/usr/bin/env bash
# Proves the roles work by logging in as each database user. Every "must fail" line should say "FAIL-EXPECTED (good)".
# Run after build.sh. WARNING: if the roles were wrong, the DROP attempts below could really drop a table; run build.sh again afterwards.
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
bad=0
as() { MYSQL_PWD="$2" my --user="$1" "$DB_NAME" -t -e "$3"; }
must_work() { if out=$(as "$1" "$2" "$3" 2>&1); then echo "OK            $4"; echo "$out" | head -6 | sed 's/^/              /'; else echo "UNEXPECTED FAILURE: $4: $out"; bad=1; fi; }
must_fail() { if out=$(as "$1" "$2" "$3" 2>&1); then echo "UNEXPECTED SUCCESS: $4"; bad=1; else echo "FAIL-EXPECTED (good) $4 -> $(echo "$out" | tr '\n' ' ' | cut -c1-120)"; fi; }

echo "=== analyst_user ==="
must_work analyst_user "$ANALYST_DB_PASSWORD" "SELECT first_name_masked, email_masked, phone_masked, city FROM v_customer_orders_masked LIMIT 3" "analyst reads the masked view"
must_fail analyst_user "$ANALYST_DB_PASSWORD" "SELECT email FROM customers LIMIT 1" "analyst reading raw customers"
must_fail analyst_user "$ANALYST_DB_PASSWORD" "DELETE FROM orders WHERE order_id = 1" "analyst DELETE"
must_fail analyst_user "$ANALYST_DB_PASSWORD" "UPDATE products SET price = 1" "analyst UPDATE"
must_fail analyst_user "$ANALYST_DB_PASSWORD" "DROP TABLE orders" "analyst DROP TABLE"
echo "=== app_user ==="
must_work app_user "$APP_DB_PASSWORD" "SELECT COUNT(*) AS products FROM products" "app reads products"
must_fail app_user "$APP_DB_PASSWORD" "DROP TABLE orders" "app DROP TABLE"
must_fail app_user "$APP_DB_PASSWORD" "TRUNCATE TABLE orders" "app TRUNCATE"
must_fail app_user "$APP_DB_PASSWORD" "DELETE FROM orders WHERE order_id = 1" "app DELETE on orders"
must_fail app_user "$APP_DB_PASSWORD" "UPDATE audit_log SET action = 'INSERT'" "app editing audit_log"
must_fail app_user "$APP_DB_PASSWORD" "UPDATE products SET price = 1" "app changing prices directly"
echo "=== admin_user ==="
must_work admin_user "$ADMIN_DB_PASSWORD" "SELECT COUNT(*) AS audit_rows FROM audit_log" "admin reads the audit log"
must_fail admin_user "$ADMIN_DB_PASSWORD" "DROP TABLE reviews" "admin DROP TABLE"
echo "=== password storage ==="
my "$DB_NAME" -t -e "SELECT CONCAT(SUM(password_hash LIKE 'pbkdf2_sha256\$%'), ' of ', COUNT(*)) AS customers_with_salted_pbkdf2_hash FROM customers"
[ "$bad" = 0 ] && echo "ALL SECURITY CHECKS PASSED" || { echo "SECURITY CHECK PROBLEM, see above"; exit 1; }
