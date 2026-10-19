# Availability: what "always online" means here

No cloud service can honestly promise 100% uptime; Cloudflare, Aiven, AWS and Google all publish SLAs below 100%. What this design does is make
the site *look* online almost all of the time, and fail gently on the rare occasion the database is not reachable.

## What runs where
| Piece | Where | Why it stays up |
| --- | --- | --- |
| Pages, logic, login | Cloudflare Worker, run on Cloudflare's global network | No server of ours to crash or reboot |
| Database | MySQL 8 on Aiven | Managed service with automatic backups |
| Connection | Cloudflare Hyperdrive | Pools connections, so traffic spikes do not exhaust the database's connection limit |
| Saved copy of read-only pages | Cloudflare KV | Still available when the database is not |

## What happens when the database is unreachable
- **Price list, stock page, reports:** still load from the saved copy, with a banner saying the data is from the last good copy and orders are paused.
- **Login, checkout, my orders:** show a friendly "temporarily unavailable, nothing has been lost" page (HTTP 503) instead of a crash. Customers who are already logged in stay logged in, because the session lives in a signed cookie, not in the database.
- **`/health`** always answers (HTTP 200) with `{"site":"ok","database":"down"}`; `/health?strict` returns 503 so an uptime monitor can alert.
- Orders are never half-saved: each procedure is one transaction.
All of this is covered by automated tests (`worker/tests/test.mjs`, section "the database goes down").

## Keeping the database awake and watched
`wrangler.toml` schedules a Worker every 30 minutes. It runs `SELECT 1` (so a free Aiven service is not idle), refreshes the saved copies, and, if the database does not answer, posts a message to `ALERT_WEBHOOK_URL` (for example a free ntfy.sh topic on your phone).

## The limit of the free database
Aiven's free MySQL plan is a single node with no SLA, and Aiven's documentation says it may be powered off after a period of no activity (and warns first). The 30-minute check reduces that risk but Aiven does not promise it prevents it. If the database is powered off, switch it on in the Aiven console; the site keeps serving saved pages meanwhile.

## If you need a stronger guarantee (paid options)
- Aiven paid MySQL plans with a standby node and automatic failover.
- Amazon RDS or Google Cloud SQL MySQL with Multi-AZ / high availability. Hyperdrive supports both, so only the Hyperdrive connection string changes; the app does not.
Do this only for the marking period, then switch it off.

## Demo-day insurance
Record a screen capture of the full demo (`docs/demo_script.md`). The only failure no hosting can fix is the room's internet.
