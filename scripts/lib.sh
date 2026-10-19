# lib.sh : shared settings for the scripts. Source it; do not run it.
# Connection settings come from environment variables (see .env.example):
#   DB_HOST DB_PORT DB_USER DB_PASSWORD DB_NAME   and optionally DB_SSL_MODE (REQUIRED|VERIFY_CA|...) and DB_SSL_CA (path to ca.pem)
# Defaults point at a local MySQL (handy for rehearsing on your own machine before touching Aiven).
: "${DB_HOST:=127.0.0.1}" "${DB_PORT:=3306}" "${DB_USER:=root}" "${DB_NAME:=ecommerce}"
export MYSQL_PWD="${DB_PASSWORD:-}"
SSL_ARGS=()
[ -n "${DB_SSL_MODE:-}" ] && SSL_ARGS+=("--ssl-mode=${DB_SSL_MODE}")
[ -n "${DB_SSL_CA:-}" ]   && SSL_ARGS+=("--ssl-ca=${DB_SSL_CA}")
APP_DB_PASSWORD="${APP_DB_PASSWORD:-ChangeMe_App_1}"
ANALYST_DB_PASSWORD="${ANALYST_DB_PASSWORD:-ChangeMe_Analyst_1}"
ADMIN_DB_PASSWORD="${ADMIN_DB_PASSWORD:-ChangeMe_Admin_1}"
# my [mysql options] [database] : the mysql client with this project's connection settings
my() { mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" ${SSL_ARGS[@]+"${SSL_ARGS[@]}"} --default-character-set=utf8mb4 "$@"; }
command -v mysql >/dev/null 2>&1 || { echo "The 'mysql' client is not installed. Install MySQL Client (or MySQL Workbench) first." >&2; exit 1; }
