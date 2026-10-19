#!/usr/bin/env bash
# Usage: scripts/backup.sh [backup_folder]   Makes a dated, compressed dump (tables, data, routines, triggers) and keeps the last 7.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
command -v mysqldump >/dev/null || { echo "mysqldump is not installed"; exit 1; }
DIR=${1:-backups}; mkdir -p "$DIR"
FILE="$DIR/${DB_NAME}_$(date +%Y%m%d_%H%M%S).sql.gz"
mysqldump --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" ${SSL_ARGS[@]+"${SSL_ARGS[@]}"} \
  --single-transaction --routines --triggers --no-tablespaces "$DB_NAME" | gzip > "$FILE"
ls -1t "$DIR"/${DB_NAME}_*.sql.gz | tail -n +8 | xargs -r rm --
echo "Backup written: $FILE"
echo "Restore with:  gunzip -c $FILE | mysql --host=... --user=... $DB_NAME"
