// tests/test.mjs : runs the Worker in Node against a FAKE database (no MySQL needed) and checks every page and rule path.
// This tests the web app's logic. The SQL itself is tested by scripts/build.sh and scripts/*_test.sh against a real MySQL.
// Run:  node tests/test.mjs
import worker, { loadReports } from '../src/index.js';
import { verifyPassword, signToken } from '../src/util.js';

const HASH = {
  3: 'pbkdf2_sha256$100000$QB/06z6rALSC0gcJYcBvRg==$jg0u3UiLstfTNkfp5ARYJxFgos1Vtqdf6tPYGeH9m64=',
  1: 'pbkdf2_sha256$100000$n2SlrTILcfEyFgzTWB5mnQ==$XaelLfoAk7Klhw9nqyPUtsXxPX8VUBlWhH/qa8uk5HQ=',
  2: 'pbkdf2_sha256$100000$zl/y6O7dCtwQ7QaNqZmrIQ==$Oo0eP9YuCv89njhqAP+lEV+ZPxfboub6762ZJF/9LeA=',
};
const USERS = {
  'bwalya.chilufya3@example.com': { customer_id: 3, first_name: 'Bwalya', last_name: 'Chilufya', password_hash: HASH[3], role: 'customer' },
  'mwila.zulu1@example.com': { customer_id: 1, first_name: 'Mwila', last_name: 'Zulu', password_hash: HASH[1], role: 'admin' },
  'chanda.phiri2@example.com': { customer_id: 2, first_name: 'Chanda', last_name: 'Phiri', password_hash: HASH[2], role: 'analyst' },
};
const PRODUCTS = [
  { product_id: 8, name: 'Wireless Earbuds', category: 'Accessories', price: '650.00', stock_quantity: 70, reorder_level: 15, avg_rating: '4.1', reviews: 5 },
  { product_id: 19, name: 'Cast Iron <script>alert(1)</script>', category: 'Cookware', price: '900.00', stock_quantity: 2, reorder_level: 6, avg_rating: null, reviews: 0 },
];

// ---- fake MySQL connection ----
const log = [];
let dbDown = false, failPlace = null;
const fake = {
  async query(sql, params = []) {
    log.push({ sql: sql.replace(/\s+/g, ' ').trim(), params });
    if (dbDown) throw Object.assign(new Error('connect ECONNREFUSED'), { code: 'ECONNREFUSED' });
    const q = sql.replace(/\s+/g, ' ').trim();
    if (q === 'SELECT 1') return [[{ 1: 1 }]];
    if (q.includes('FROM customers WHERE email = ?')) return [USERS[params[0]] ? [USERS[params[0]]] : []];
    if (q.includes('FROM products p JOIN categories c')) return [PRODUCTS];
    if (q.includes('FROM products WHERE is_active AND product_id IN')) return [PRODUCTS.filter((p) => params[0].includes(p.product_id))];
    if (q.includes('FROM addresses WHERE customer_id')) return [[{ address_id: 11, street: '12 Cairo Rd', city: 'Lusaka', is_default: 1 }]];
    if (q.startsWith('CALL place_order_rs')) {
      if (failPlace) throw Object.assign(new Error('x'), { sqlState: '45000', sqlMessage: failPlace });
      return [[[{ order_id: 501 }], { affectedRows: 0 }]];
    }
    if (q.startsWith('CALL pay_order') || q.startsWith('CALL cancel_order') || q.startsWith('CALL refund_order')) return [{ affectedRows: 1 }];
    if (q.includes('SELECT customer_id FROM orders WHERE order_id')) return [[{ customer_id: params[0] === 700 ? 99 : 3 }]];
    if (q.startsWith('UPDATE orders SET status')) return [{ affectedRows: 1 }];
    if (q.includes('FROM orders o JOIN order_items i')) return [[{ order_id: 500, order_date: '2026-10-01 10:00:00', status: 'placed', total_amount: '650.00', items: 'Wireless Earbuds x1' }]];
    if (q.includes('FROM orders o JOIN customers cu')) return [[{ order_id: 500, order_date: '2026-10-01 10:00:00', status: 'paid', total_amount: '650.00', customer: 'Bwalya Chilufya', city: 'Lusaka' }]];
    if (q.includes('FROM audit_log')) return [[{ audit_id: 1, table_name: 'orders', record_id: 500, action: 'UPDATE', changed_by: 'app_user', changed_at: '2026-10-01 10:00:00', new_value: '{"status":"paid"}' }]];
    if (q.includes('COUNT(DISTINCT customer_id) AS customers')) return [[{ orders: 100, revenue: '200000.00', customers: 30 }]];
    if (q.includes('FROM v_monthly_revenue')) return [[{ month: '2026-01-01', orders: 5, revenue: '1000' }, { month: '2026-02-01', orders: 8, revenue: '3000' }, { month: '2026-03-01', orders: 6, revenue: '2000' }]];
    if (q.includes('FROM v_top_products')) return [[{ name: 'Laptop', units_sold: 3, revenue: '37500' }]];
    if (q.includes('GROUP BY a.city')) return [[{ city: 'Kitwe', orders: 38, revenue: '66831' }]];
    if (q.includes('FROM payments GROUP BY method')) return [[{ method: 'mobile_money', attempts: 90, share_pct: '57.3', failure_rate_pct: '4.4' }]];
    if (q.includes('FROM orders GROUP BY status')) return [[{ status: 'delivered', orders: 134 }]];
    if (q.includes('FROM v_low_stock')) return [[{ name: 'Blender', stock_quantity: 3, reorder_level: 8 }]];
    throw new Error('FAKE DB: unexpected SQL ' + q);
  },
};

// ---- fake KV ----
const kvStore = new Map();
const KV = { async get(k) { return kvStore.has(k) ? JSON.parse(kvStore.get(k)) : null; }, async put(k, v) { kvStore.set(k, v); } };
const env = { SESSION_SECRET: 'test-secret-test-secret', SHOP_NAME: 'Zed Market', CACHE: KV, __testConn: fake };
const ctx = { waitUntil: (p) => pending.push(p) }; const pending = [];

// ---- tiny browser ----
let jar = {};
const reset = () => { jar = {}; };
async function call(path, { method = 'GET', form, headers = {} } = {}) {
  const h = new Headers({ cookie: Object.entries(jar).map(([k, v]) => `${k}=${v}`).join('; '), ...headers });
  const init = { method, headers: h };
  if (form) { const f = new FormData(); for (const [k, v] of Object.entries(form)) f.append(k, v); init.body = f; }
  const res = await worker.fetch(new Request('https://shop.example' + path, init), env, ctx);
  await Promise.all(pending.splice(0));
  for (const c of res.headers.getSetCookie()) { const [kv] = c.split(';'); const i = kv.indexOf('='); const k = kv.slice(0, i), v = kv.slice(i + 1); if (v === '' || /Max-Age=0/.test(c)) delete jar[k]; else jar[k] = v; }
  return { status: res.status, text: await res.text(), headers: res.headers, location: res.headers.get('location') };
}
async function follow(res) { return res.location ? call(res.location) : res; }
async function login(email) { reset(); const r = await call('/login', { method: 'POST', form: { email, password: 'Demo#2026' } }); return r; }

let pass = 0, fail = 0;
function check(name, cond, extra = '') { if (cond) { pass++; console.log('PASS', name); } else { fail++; console.log('FAIL', name, extra); } }

// ================= tests =================
// 1. public price list, escaping, search
let r = await call('/');
check('price list loads for a visitor', r.status === 200 && r.text.includes('Wireless Earbuds') && r.text.includes('Log in to buy'));
check('product names are HTML-escaped (no script injection)', !r.text.includes('<script>alert(1)</script>') && r.text.includes('&lt;script&gt;'));
check('security headers are set', r.headers.get('content-security-policy').includes("default-src 'self'") && r.headers.get('x-frame-options') === 'DENY');
r = await call('/?q=earbuds');
check('search filters the list', r.text.includes('Wireless Earbuds') && !r.text.includes('Cast Iron'));
check('price list was saved to the cache', kvStore.has('catalogue'));

// 2. password check uses the real seeded hashes
check('seed hash verifies the demo password', await verifyPassword('Demo#2026', HASH[3]));
check('seed hash rejects a wrong password', !(await verifyPassword('wrong', HASH[3])));

// 3. login
reset(); r = await call('/login', { method: 'POST', form: { email: 'bwalya.chilufya3@example.com', password: 'nope' } });
check('wrong password is refused', r.status === 200 && r.text.includes('Wrong email or password') && !jar.session);
r = await call('/login', { method: 'POST', form: { email: 'nobody@example.com', password: 'x' } });
check('unknown email gives the same message', r.text.includes('Wrong email or password'));
log.length = 0;
r = await call('/login', { method: 'POST', form: { email: "x' OR '1'='1", password: 'x' } });
check('SQL injection text is passed as a parameter, never inside the SQL', log.some((l) => l.params[0] === "x' or '1'='1") && !log.some((l) => l.sql.includes("OR '1'='1")));
r = await login('bwalya.chilufya3@example.com');
check('customer login sets a session cookie and redirects', r.status === 303 && !!jar.session && r.location === '/');

// 4. cart + checkout
r = await call('/cart/add', { method: 'POST', form: { product_id: 8, qty: 2 } });
check('add to cart', r.status === 303 && !!jar.cart);
r = await call('/cart');
check('cart shows the line and total', r.text.includes('Wireless Earbuds') && r.text.includes('K1,300.00'));
r = await call('/checkout');
check('checkout shows the address and payment methods', r.text.includes('12 Cairo Rd') && r.text.includes('Mobile money'));
log.length = 0;
r = await call('/checkout', { method: 'POST', form: { address_id: 11, method: 'mobile_money' } });
const place = log.find((l) => l.sql.startsWith('CALL place_order_rs')), pay = log.find((l) => l.sql.startsWith('CALL pay_order'));
check('checkout calls the database procedures, not its own logic', !!place && !!pay);
check('place_order gets customer, address and a JSON list of items', place && place.params[0] === 3 && place.params[1] === 11 && place.params[2] === '[{"product_id":8,"quantity":2}]', JSON.stringify(place && place.params));
check('pay_order gets the new order id, method and success flag', pay && pay.params[0] === 501 && pay.params[1] === 'mobile_money' && pay.params[2] === 1, JSON.stringify(pay && pay.params));
r = await follow(r);
check('success message shown', r.text.includes('Order #501 placed and paid'));
r = await call('/cart');
check('cart is empty after the order', r.text.includes('Your cart is empty'));

// 5. demo failed payment
await call('/cart/add', { method: 'POST', form: { product_id: 8, qty: 1 } });
log.length = 0;
r = await call('/checkout', { method: 'POST', form: { address_id: 11, method: 'card', fail: '1' } });
check('"make this payment fail" sends success flag 0', log.find((l) => l.sql.startsWith('CALL pay_order')).params[2] === 0);
r = await follow(r);
check('failed payment message', r.text.includes('payment failed'));

// 6. a database rule (out of stock) is shown as a message, not an error page
await call('/cart/add', { method: 'POST', form: { product_id: 19, qty: 3 } });
failPlace = 'Insufficient stock for product 19: requested 3, available 2';
r = await call('/checkout', { method: 'POST', form: { address_id: 11, method: 'card' } });
r = await follow(r);
check('oversell: the database message reaches the user', r.status === 200 && r.text.includes('Insufficient stock for product 19'));
failPlace = null;

// 7. orders page + ownership
r = await call('/orders');
check('my orders lists the order with Pay and Cancel', r.text.includes('#500') && r.text.includes('Pay') && r.text.includes('Cancel'));
r = await call('/orders/700/cancel', { method: 'POST', form: {} }); r = await follow(r);
check("cannot cancel someone else's order", r.text.includes('That order is not yours'));
log.length = 0;
r = await call('/orders/500/cancel', { method: 'POST', form: {} });
check('own order cancel calls cancel_order', log.some((l) => l.sql.startsWith('CALL cancel_order') && l.params[0] === 500));

// 8. role protection
r = await call('/admin/orders'); check('customer cannot open admin orders', r.status === 403);
r = await call('/reports'); check('customer cannot open reports', r.status === 403);
r = await call('/admin/orders/500/refund', { method: 'POST', form: {} }); check('customer cannot refund', r.status === 403);
reset(); r = await call('/admin/audit'); check('visitor is sent to log in', r.status === 303 && r.location === '/login');
r = await call('/logout', { method: 'POST', form: {} });
check('logout clears the session', !jar.session);

// 9. tampered cookie
reset(); await login('bwalya.chilufya3@example.com');
const [body, sig] = jar.session.split('.');
const forged = Buffer.from(JSON.stringify({ uid: 3, name: 'Bwalya', role: 'admin', exp: Date.now() + 1e7 })).toString('base64url');
jar.session = forged + '.' + sig;
r = await call('/admin/orders');
check('a forged "admin" cookie is rejected', r.status === 303 && r.location === '/login');
jar.session = await signToken({ uid: 3, name: 'Old', role: 'admin', exp: Date.now() - 1000 }, env.SESSION_SECRET);
r = await call('/admin/orders');
check('an expired session is rejected', r.status === 303);

// 10. other-site form posts
r = await call('/login', { method: 'POST', form: { email: 'a', password: 'b' }, headers: { origin: 'https://evil.example' } });
check('a POST from another website is refused', r.status === 403);

// 11. admin
r = await login('mwila.zulu1@example.com');
check('admin goes to the orders screen', r.location === '/admin/orders');
r = await call('/admin/orders'); check('admin orders page', r.status === 200 && r.text.includes('Bwalya Chilufya') && r.text.includes('Mark shipped') && r.text.includes('Refund'));
log.length = 0; r = await call('/admin/orders/500/ship', { method: 'POST', form: {} });
check('ship updates the status through the database guard trigger', log.some((l) => l.sql.startsWith("UPDATE orders SET status = 'shipped'") && l.params[0] === 500));
log.length = 0; r = await call('/admin/orders/500/refund', { method: 'POST', form: {} });
check('refund calls refund_order', log.some((l) => l.sql.startsWith('CALL refund_order')));
r = await call('/admin/stock'); check('stock page flags low stock', r.text.includes('Reorder'));
r = await call('/admin/audit'); check('audit log page', r.text.includes('app_user') && r.text.includes('orders #500'));

// 12. analyst: reports yes, admin pages no, no personal data
r = await login('chanda.phiri2@example.com'); check('analyst goes to reports', r.location === '/reports');
r = await call('/reports');
check('reports show KPIs and charts', r.status === 200 && r.text.includes('K200,000.00') && r.text.includes('<svg') && r.text.includes('Kitwe'));
r = await call('/admin/orders'); check('analyst cannot open admin orders', r.status === 403);
check('reports were saved to the cache', kvStore.has('reports'));

// 13. the database goes down
dbDown = true;
r = await call('/reports');
check('database down: reports still load from the saved copy, with a notice', r.status === 200 && r.text.includes('not answering') && r.text.includes('K200,000.00'));
reset(); r = await call('/');
check('database down: the price list still loads, buying is paused', r.status === 200 && r.text.includes('Wireless Earbuds') && r.text.includes('not answering'));
r = await call('/health'); const hj = JSON.parse(r.text);
check('health: site ok, database down, still HTTP 200', r.status === 200 && hj.site === 'ok' && hj.database === 'down');
r = await call('/health?strict'); check('health?strict returns 503 when the database is down', r.status === 503);
r = await call('/login', { method: 'POST', form: { email: 'bwalya.chilufya3@example.com', password: 'Demo#2026' } });
check('database down: login shows a friendly 503 page, not a crash', r.status === 503 && r.text.includes('Temporarily unavailable'));
kvStore.clear();
r = await call('/'); check('database down and no saved copy: friendly 503', r.status === 503);
dbDown = false;
r = await call('/health'); check('database back: health says up', JSON.parse(r.text).database === 'up');

// 14. scheduled health check refreshes the cache
kvStore.clear();
await worker.scheduled({}, env, ctx); await Promise.all(pending.splice(0));
check('cron health check refreshes both saved copies', kvStore.has('catalogue') && kvStore.has('reports'));
let alerted = null; const realFetch = globalThis.fetch; globalThis.fetch = async (u, o) => { alerted = { u, body: o.body }; return new Response('ok'); };
dbDown = true; env.ALERT_WEBHOOK_URL = 'https://ntfy.example/topic';
await worker.scheduled({}, env, ctx); await Promise.all(pending.splice(0));
check('cron sends an alert when the database is down', alerted && alerted.body.includes('database check failed'));
globalThis.fetch = realFetch; dbDown = false;

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
