# Demo script (about 12 minutes)
Rehearse twice. Before each run: `demo/reset_demo.sh`. Have these open: the live site, a terminal with the `.env` loaded, Aiven console, Cloudflare dashboard.
Record a screen capture of one clean run as insurance.

| Min | Who | What | Show |
| --- | --- | --- | --- |
| 0-1 | A | The problem and the architecture | `docs/architecture.png`: green = built, dashed = production target; Cloudflare in front, MySQL on Aiven |
| 1-3 | B | Rebuild the database live | `demo/reset_demo.sh`: reset, schema, seed, procedures; point at the consistency lines (all 0) |
| 3-5 | B | Database rules | `mysql ... < demo/live_demo.sql`: place, pay (stock drops), failed payment, oversell blocked, refund, audit trail |
| 5-6 | C | Security | `scripts/security_test.sh`: analyst DELETE and DROP fail; masked view; passwords are hashes |
| 6-8 | C | The live site as a customer | Search, add to cart, checkout, try "make this payment fail", My orders |
| 8-9 | D | The site as admin | Mark the order shipped then delivered; Stock; Audit log shows the changes |
| 9-10 | D | The site as analyst | Reports: revenue trend, top products, city, payment methods, funnel, low stock |
| 10-11 | E | Big Data | Spark job output, `verify_match.py` = ALL MATCH, partition pruning, 28% Parquet size; scalability table |
| 11-12 | E | Availability | `/health`; explain the saved-copy design and the 30-minute check; what free-tier Aiven does not promise |

## If something goes wrong
- **Site shows "not answering":** open the Aiven console; if the service is powered off, power it on (about a minute). Meanwhile the price list and reports still load from the saved copy: say so, it is the design working.
- **Login error 1102:** see "Things that can bite" in `docs/deploy.md`.
- **Data looks changed:** `demo/reset_demo.sh`.
- **No internet in the room:** play the recording.
