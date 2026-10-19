# Deploying: Cloudflare Worker + MySQL on Aiven

You need: a Cloudflare account, an Aiven account, Node.js 20 or newer, and the `mysql` command-line client (or run the .sql files in MySQL Workbench).
Allow about 45 minutes the first time. Do the steps in order.

## 1. Create the database on Aiven
1. In the Aiven console create a service: **MySQL**, plan **Free**, region closest to Lusaka that the free plan offers (Europe is fine).
2. When it shows **Running**, open its overview and note **Host**, **Port**, **User** (`avnadmin`) and **Password**. Download the **CA certificate** (`ca.pem`).
3. Leave "Allowed IP addresses" at its default (open). The free plan has no static IPs, and Cloudflare's connection addresses are not fixed.

## 2. Settings file
```
cp .env.example .env        # then edit .env: DB_HOST, DB_PORT, DB_USER, DB_PASSWORD
set -a; source .env; set +a
```
Choose three different strong passwords for `APP_DB_PASSWORD`, `ANALYST_DB_PASSWORD`, `ADMIN_DB_PASSWORD`. Use only letters, digits and `_ - .` in them (no `& \ / @ : %`), which keeps the scripts and the connection string simple.
Aiven's default database is `defaultdb`. `scripts/build.sh` tries to create `ecommerce`; if Aiven refuses, create a database named `ecommerce` in the console, or set `DB_NAME=defaultdb` in `.env`.

## 3. Build and test the database
```
scripts/build.sh
```
It resets, creates the 9 tables, loads the data, installs the triggers and procedures, runs the consistency checks (every line must say 0) and the business-rule and bad-insert tests (every line PASS), rebuilds clean, then creates the roles and users.
Then:
```
scripts/security_test.sh     # analyst DELETE/DROP must fail ("FAIL-EXPECTED (good)"); ends with ALL SECURITY CHECKS PASSED
scripts/app_role_test.sh     # app_user places and pays an order through the procedures; the audit rows appear
scripts/run_queries.sh       # writes docs/query_results.txt and docs/explain_evidence.txt (evidence for the report)
scripts/build.sh             # run once more to reset the data after those tests
```
**If something fails here, stop and fix it before Cloudflare.** Common causes:
| Message | Meaning and fix |
| --- | --- |
| `ERROR 1419 ... SUPER privilege and binary logging is enabled` | The server will not let `avnadmin` create triggers/procedures. Send me the exact message; the fix is a server setting or a small change to the SQL. |
| `ERROR 1227` or `Access denied` on `CREATE ROLE` / `SET DEFAULT ROLE` | Handled automatically: build.sh switches to `sql/09b_security_no_roles.sql`. |
| `ERROR 1044` on `CREATE DATABASE` | Create the database in the console, or use `DB_NAME=defaultdb`. |
| `mysql: command not found` | Install the MySQL client, or paste each `sql/*.sql` file into MySQL Workbench in the same order as build.sh. |

## 4. Cloudflare setup
```
cd worker
npm install
npx wrangler login
```
**Hyperdrive** (the database connection). Use the *app_user* account, not avnadmin:
```
npx wrangler hyperdrive create zed-market-db --connection-string="mysql://app_user:APP_PASSWORD@HOST:PORT/ecommerce"
```
Copy the `id` it prints into `wrangler.toml` (`CHANGE_ME_HYPERDRIVE_ID`). Aiven requires an encrypted connection; if Hyperdrive reports a TLS or certificate error, see Cloudflare's Hyperdrive documentation for the MySQL TLS options and use the CA certificate from step 1.

**KV** (saved copy of read-only pages):
```
npx wrangler kv namespace create CACHE
```
Copy its id into `wrangler.toml` (`CHANGE_ME_KV_ID`).

**Secret** (signs login cookies; never put it in a file):
```
openssl rand -base64 32          # copy the output
npx wrangler secret put SESSION_SECRET   # paste it when asked
```

## 5. Test, then deploy
```
npm test            # 52 checks of the web app against a fake database; must end "0 failed"
npx wrangler deploy
```
Wrangler prints the address, like `https://zed-market.YOUR-NAME.workers.dev`. Open it.

## 6. Check it works end to end
1. `https://.../health` shows `{"site":"ok","database":"up",...}`.
2. Log in as the demo customer, add an item, check out (try the "make this payment fail" box once), look at **My orders**.
3. Log in as the demo admin, mark the order shipped and delivered, open **Stock** and **Audit log**.
4. Log in as the demo analyst, open **Reports**.
Demo accounts and password are on the login page.

## 7. Alerts (optional, 2 minutes)
Pick a hard-to-guess topic name, install the free **ntfy** app on your phone and subscribe to it, then set `ALERT_WEBHOOK_URL = "https://ntfy.sh/your-topic"` in `wrangler.toml` and run `npx wrangler deploy` again. You get a message if the database stops answering.

## 8. Big Data prototype (Stage 7)
```
pip install pymysql pyspark pandas pyarrow         # Spark also needs Java 17 or 21
python3 bigdata/export_to_csv.py
python3 bigdata/generate_clickstream.py
python3 bigdata/spark_analytics.py
python3 bigdata/verify_match.py                    # must print RESULT: ALL MATCH
```
Run it on a freshly built database; orders placed in the web app after the export will make the numbers differ.

## Things that can bite on the free plans
- **Login can fail with Cloudflare error 1102 ("exceeded CPU")** on Workers Free, because checking a 100,000-round password hash takes more CPU than the free plan's 10 ms limit may allow. Test a login right after deploying. If it fails: use Workers Paid ($5 a month, 30 s CPU limit), or regenerate the seed with fewer rounds (`ITERATIONS` in `data/generate_seed.py`, for example 10000) and run `scripts/build.sh` again; the Worker reads the round count from each stored hash, so no code change is needed. Fewer rounds is weaker, so say so in the report.
- **Aiven may power off an idle free database.** See `docs/availability.md`.
- **KV free tier** allows 1,000 writes a day; this app writes about 100.
