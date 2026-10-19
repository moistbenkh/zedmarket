#!/usr/bin/env bash
# Puts the database back to the clean seeded state (about 20 seconds). Run this before every rehearsal and before the real demo.
# Usage: demo/reset_demo.sh      (needs the DB_* settings: set -a; source .env; set +a)
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build.sh --no-tests
echo "Demo database reset. Wait about a minute for the web app's saved copies to refresh, or just reload the pages."
