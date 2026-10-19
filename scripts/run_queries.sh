#!/usr/bin/env bash
# Runs all 15 queries and writes the output to docs/query_results.txt (the evidence for the report).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
OUT=docs/query_results.txt; : > "$OUT"
for f in queries/q*.sql; do
  echo "=== $(basename "$f")" >> "$OUT"
  my -t "$DB_NAME" < "$f" >> "$OUT"; echo >> "$OUT"
done
my -t "$DB_NAME" < sql/08_explain_evidence.sql > docs/explain_evidence.txt
echo "Wrote $OUT and docs/explain_evidence.txt"
