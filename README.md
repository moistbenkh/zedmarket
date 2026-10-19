# E-Commerce Customer and Sales Analytics (MySQL on Aiven, web app on Cloudflare)

Big Data mid-semester project. A relational MySQL 8 database for an online shop in Zambia (ZMW), analysed with 15 SQL queries, a Big Data layer
(Spark prototype and architecture), and a web app that runs on Cloudflare's network. All data is fictional.

```
Browser -> Cloudflare Worker (pages + logic) -> Hyperdrive -> MySQL 8 on Aiven
                       |                                         (stored procedures + triggers hold the business rules)
                       +-> Cloudflare KV (saved copy of read-only pages, used if the database is unreachable)
```
Start with **docs/deploy.md** (45 minutes, step by step). How availability is handled, and its honest limits: **docs/availability.md**.

## What is where
| Path | What it is |
| --- | --- |
| sql/01_schema.sql ... 09_security.sql | Schema (9 tables), seed data, triggers and procedures, views, tests, roles. `09b_security_no_roles.sql` is the fallback |
| scripts/build.sh | One command: reset, build, self-tests, roles. Also `security_test.sh`, `app_role_test.sh`, `run_queries.sh`, `backup.sh` |
| queries/q01..q15 | The 15 analytics queries, each with the business question, SQL concepts and a one-line interpretation |
| worker/ | The web app (Cloudflare Worker): login and roles, price list and search, cart, checkout, orders, admin screens, reports, `/health` |
| worker/tests/test.mjs | 52 automated checks of the web app, including database-down behaviour (`cd worker && npm test`) |
| bigdata/ | CSV export, synthetic clickstream, PySpark job, Spark-versus-MySQL check |
| charts/ | 3 charts (PNG), their CSV sources, make_charts.py |
| docs/ | ERD, architecture diagram, Big Data architecture, scalability discussion, security notes, availability, demo script, deploy guide |
| demo/ | `reset_demo.sh` and `live_demo.sql` for the live demonstration |
| data/generate_seed.py | Regenerates `sql/02_seed.sql` (fixed random seed; password hashes are PBKDF2) |

## Quick start
```
cp .env.example .env && edit it && set -a && source .env && set +a
scripts/build.sh && scripts/security_test.sh && scripts/run_queries.sh && scripts/build.sh
cd worker && npm install && npm test        # then the Cloudflare steps in docs/deploy.md
```
Demo logins (password `Demo#2026`): customer `bwalya.chilufya3@example.com`, admin `mwila.zulu1@example.com`, analyst `chanda.phiri2@example.com`.

## What has and has not been tested (read this before the demo)
- **Tested here:** the web app's logic (52 checks in `worker/tests/test.mjs`, using a fake database): routes, roles, forged and expired cookies, SQL parameters, the stored-procedure calls and their arguments, database-rule messages, saved-copy behaviour when the database is down, health check and alerts. Password verification against the real seeded hashes. The diagrams render.
- **Not run here:** the SQL itself. The build environment had no MySQL server, so `sql/*.sql` and `queries/*.sql` were reviewed line by line against MySQL 8 rules but **not executed**. The first real run is `scripts/build.sh` against Aiven (deploy.md step 3). Its built-in tests (consistency, 8 business-rule checks, 8 bad inserts, security checks) will show immediately if anything needs a fix.
- **Not run here:** the connection from Cloudflare to Aiven through Hyperdrive, and a live login on the Workers Free CPU limit (see deploy.md, "Things that can bite").
- **From the earlier PostgreSQL build, same data:** the Spark results in `bigdata/out/` and the 3 charts. The seed is unchanged (160 orders, K302,915 revenue), but re-run `bigdata/verify_match.py` against Aiven to regenerate the evidence. `docs/query_results.txt` is produced by `scripts/run_queries.sh`.
