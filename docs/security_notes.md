# Security notes (MySQL on Aiven, web app on Cloudflare)

## Implemented
**In the database** (`sql/09_security.sql`, tested by `scripts/security_test.sh`)
- Three roles: `app_role` (read, change order status, run the order procedures; no INSERT/DELETE/DROP; cannot touch `audit_log`), `analyst_role` (SELECT on views and non-personal tables only, no `customers` table), `admin_role` (read/write all data including the audit log, but no DROP/ALTER/CREATE).
- Three login users (`app_user`, `analyst_user`, `admin_user`). MySQL stores their passwords as salted hashes (caching_sha2_password).
- `v_customer_orders_masked` hides names, emails and phones. Analysts get this view instead of the customers table.
- Procedures and triggers run with their owner's rights, so the app can place orders and the audit trigger still writes `audit_log` even though `app_user` cannot write to it.
- `scripts/backup.sh` makes a dated, compressed dump with routines and triggers and keeps the last 7. Aiven also takes its own automatic backups.
- If the host refuses `CREATE ROLE`, `scripts/build.sh` automatically applies `sql/09b_security_no_roles.sql`, which grants the same privileges directly to the users.

**In the web app** (`worker/`)
- Customer passwords are stored only as salted PBKDF2-SHA256 hashes (100,000 iterations, the most the Workers runtime allows). Verified with a constant-time comparison. An unknown email takes as long as a wrong password.
- Every database value is passed as a parameter, never joined into the SQL text (test: "SQL injection text is passed as a parameter").
- Sessions are signed cookies (HMAC-SHA256, 8 hours, `HttpOnly; Secure; SameSite=Lax`). A forged or expired cookie is rejected (tests). The signing key is a Cloudflare secret, not in the code.
- Roles are enforced on every route: customers cannot open admin or report pages; customers can act only on their own orders.
- Form posts from another website are refused (Origin check). All output is HTML-escaped. A Content-Security-Policy, X-Frame-Options and nosniff headers are sent.
- The web app connects as `app_user` only, so even a bug in the app cannot DROP a table or edit the audit log.

## Not implemented (configuration notes for a real deployment)
- **TLS to the database:** Aiven requires TLS. For stricter checking, download Aiven's CA certificate and use `VERIFY_CA` (set `DB_SSL_CA`).
- **MFA:** add at the identity layer (for example Cloudflare Access in front of `/admin`, or an authenticator app at login).
- **WAF and rate limits:** turn on Cloudflare's WAF and a rate-limiting rule for `/login` once the site has a custom domain.
- **Network:** Aiven's free plan has no private network or static IPs, so the database accepts connections from any address and relies on TLS plus strong passwords. A paid plan can restrict access to Cloudflare's addresses or a VPC.
- **Secrets:** change the three database passwords and the demo account password (`DEMO_PASSWORD=... python3 data/generate_seed.py`) for any real use, and set `SHOW_DEMO_LOGINS = "false"`.
