// db.js : the only file that talks to MySQL. Every value goes in as a parameter (never pasted into the SQL text).
// Production: connects through Cloudflare Hyperdrive (env.HYPERDRIVE) to the MySQL on Aiven.
// Tests: env.__testConn replaces the connection with a fake (tests/test.mjs).

export async function withDb(rc, fn) {
  const { env, ctx } = rc;
  if (env.__testConn) return fn(env.__testConn);
  const { default: mysql } = await import('mysql2/promise');
  const h = env.HYPERDRIVE;
  const conn = await mysql.createConnection({
    host: h.host, port: h.port, user: h.user, password: h.password, database: h.database,
    disableEval: true,            // required in Workers (no eval)
    connectTimeout: 8000,
    charset: 'utf8mb4',
    dateStrings: true,            // DATETIME comes back as text, no timezone surprises
  });
  try { return await fn(conn); }
  finally { ctx.waitUntil(conn.end().catch(() => {})); }
}

// rows of a SELECT
export async function rows(conn, sql, params = []) { const [r] = await conn.query(sql, params); return r; }
// rows of the first result set of a CALL (procedures return [resultSets..., okPacket])
export async function callRows(conn, sql, params = []) {
  const [r] = await conn.query(sql, params);
  return Array.isArray(r) && Array.isArray(r[0]) ? r[0] : r;
}

// A rule written in the database (SQLSTATE 45000 from SIGNAL) is a message for the user.
// Anything else (cannot connect, timeout, access denied) means the database is unavailable.
export const isRuleError = (e) => e && e.sqlState === '45000';
export const ruleMessage = (e) => e.sqlMessage || e.message;

// Read-through cache: try the database; on success refresh the saved copy (at most every `fresh` seconds);
// on failure fall back to the saved copy. If there is no saved copy either, the error is thrown.
export async function cached(rc, key, loader, fresh = 600) {
  const { env, ctx } = rc;
  let hit = null;
  try { hit = env.CACHE ? await env.CACHE.get(key, 'json') : null; } catch { hit = null; }
  try {
    const data = await loader();
    if (env.CACHE && (!hit || Date.now() - hit.ts > fresh * 1000)) {
      ctx.waitUntil(env.CACHE.put(key, JSON.stringify({ ts: Date.now(), data }), { expirationTtl: 60 * 60 * 24 * 14 }).catch(() => {}));
    }
    return { data, stale: false };
  } catch (e) {
    if (hit) return { data: hit.data, stale: true, ts: hit.ts };
    throw e;
  }
}
