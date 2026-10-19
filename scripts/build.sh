#!/usr/bin/env bash
# Usage: scripts/build.sh [--no-tests] [--no-security]
# Rebuilds the whole database: reset, schema, seed, business rules, views, then the self-tests, then a clean rebuild,
# then the security roles. Works against any MySQL 8 server (local MySQL, or Aiven). Settings: see scripts/lib.sh and .env.example.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
TESTS=1; SECURITY=1
for a in "$@"; do case "$a" in --no-tests) TESTS=0;; --no-security) SECURITY=0;; *) echo "Unknown option $a"; exit 2;; esac; done

my -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4" 2>/dev/null \
  || echo "(could not CREATE DATABASE; assuming '$DB_NAME' already exists, for example created in the Aiven console)"

core() { for f in 00_reset 01_schema 02_seed 03_business_rules 05_views; do my "$DB_NAME" < "sql/$f.sql"; done; }
echo "--- building schema, data, rules, views"; core

echo "--- consistency checks (every line should say 0)"
my -t "$DB_NAME" < sql/06_consistency_check.sql

if [ "$TESTS" = 1 ]; then
  echo "--- business rule tests"
  OUT=$(my -t "$DB_NAME" < sql/04_business_rules_test.sql); echo "$OUT"
  echo "--- bad-insert tests (every statement must be rejected)"
  OUT2=$(my -t "$DB_NAME" < sql/07_bad_inserts_test.sql); echo "$OUT2"
  if echo "$OUT$OUT2" | grep -q "FAIL"; then echo "A TEST FAILED. See above."; exit 1; fi
  echo "--- tests passed; rebuilding a clean database (the tests leave two small test orders behind)"
  core
fi

if [ "$SECURITY" = 1 ]; then
  echo "--- security roles and users"
  subst() { sed -e "s/__APP_PW__/${APP_DB_PASSWORD//\//\\/}/" -e "s/__ANALYST_PW__/${ANALYST_DB_PASSWORD//\//\\/}/" \
                -e "s/__ADMIN_PW__/${ADMIN_DB_PASSWORD//\//\\/}/" -e "s/ecommerce\./${DB_NAME}./g" "$1"; }
  if ! subst sql/09_security.sql | my "$DB_NAME"; then
    echo "(roles were refused by this server; applying sql/09b_security_no_roles.sql, which grants the same privileges directly to the users)"
    subst sql/09b_security_no_roles.sql | my "$DB_NAME"
  fi
fi
echo "Done. Database '$DB_NAME' is ready."
