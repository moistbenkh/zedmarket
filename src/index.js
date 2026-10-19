// index.js : the web app. One Cloudflare Worker serves every page; MySQL (Aiven) is reached through Hyperdrive.
// Rules about stock, payments and order states live in the DATABASE (stored procedures and triggers, sql/03_business_rules.sql).
// This file only calls them, so the logic is not written twice.
import { esc, num, money, shortDate, signToken, verifyToken, parseCookies, cookie, verifyPassword, DUMMY_HASH } from './util.js';
import { withDb, rows, callRows, isRuleError, ruleMessage, cached } from './db.js';
import { layout, table, barChart, lineChart } from './ui.js';

const SESSION_HOURS = 8;
const METHODS = { mobile_money: 'Mobile money', card: 'Card', bank_transfer: 'Bank transfer', cash_on_delivery: 'Cash on delivery' };

// ------------------------------------------------------------------ queries (all parameterised)
const SQL_CATALOGUE = `
  SELECT p.product_id, p.name, c.name AS category, p.price, p.stock_quantity, p.reorder_level,
         ROUND(AVG(r.rating), 1) AS avg_rating, COUNT(r.review_id) AS reviews
    FROM products p JOIN categories c ON c.category_id = p.category_id
    LEFT JOIN reviews r ON r.product_id = p.product_id
   WHERE p.is_active
   GROUP BY p.product_id, p.name, c.name, p.price, p.stock_quantity, p.reorder_level
   ORDER BY c.name, p.name`;

export const loadCatalogue = (conn) => rows(conn, SQL_CATALOGUE);

export async function loadReports(conn) {
  const [kpi] = await rows(conn, `SELECT COUNT(*) AS orders, COALESCE(SUM(total_amount),0) AS revenue, COUNT(DISTINCT customer_id) AS customers
                                    FROM orders WHERE status IN ('paid','shipped','delivered')`);
  return {
    kpi,
    monthly: await rows(conn, `SELECT month, orders, revenue FROM v_monthly_revenue ORDER BY month`),
    topProducts: await rows(conn, `SELECT name, units_sold, revenue FROM v_top_products ORDER BY revenue DESC LIMIT 10`),
    city: await rows(conn, `SELECT a.city, COUNT(*) AS orders, SUM(o.total_amount) AS revenue
                              FROM orders o JOIN addresses a ON a.address_id = o.address_id
                             WHERE o.status IN ('paid','shipped','delivered') GROUP BY a.city ORDER BY revenue DESC`),
    payments: await rows(conn, `SELECT method, COUNT(*) AS attempts,
                                       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS share_pct,
                                       ROUND(100.0 * SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) / COUNT(*), 1) AS failure_rate_pct
                                  FROM payments GROUP BY method ORDER BY attempts DESC`),
    funnel: await rows(conn, `SELECT status, COUNT(*) AS orders FROM orders GROUP BY status
                               ORDER BY CASE status WHEN 'cart' THEN 1 WHEN 'placed' THEN 2 WHEN 'paid' THEN 3 WHEN 'shipped' THEN 4
                                                    WHEN 'delivered' THEN 5 WHEN 'cancelled' THEN 6 ELSE 7 END`),
    lowStock: await rows(conn, `SELECT name, stock_quantity, reorder_level FROM v_low_stock ORDER BY reorder_level - stock_quantity DESC`),
  };
}

// ------------------------------------------------------------------ request helpers
const SECURITY_HEADERS = {
  'content-type': 'text/html; charset=utf-8',
  'cache-control': 'no-store',
  'x-content-type-options': 'nosniff',
  'referrer-policy': 'same-origin',
  'x-frame-options': 'DENY',
  'content-security-policy': "default-src 'self'; img-src 'self' data:; style-src 'self'; form-action 'self'; frame-ancestors 'none'",
};

function respond(rc, body, status = 200) {
  const h = new Headers(SECURITY_HEADERS);
  for (const c of rc.setCookies) h.append('set-cookie', c);
  return new Response(body, { status, headers: h });
}
function redirect(rc, location, flash) {
  const h = new Headers({ location, 'cache-control': 'no-store' });
  for (const c of rc.setCookies) h.append('set-cookie', c);
  if (flash) h.append('set-cookie', cookie('flash', encodeURIComponent(flash.kind + ':' + flash.text), 30));
  return new Response(null, { status: 303, headers: h });
}
function page(rc, opts, status = 200) {
  const cartCount = rc.cart ? Object.values(rc.cart).reduce((a, b) => a + b, 0) : 0;
  return respond(rc, layout(rc, { ...opts, user: rc.user, flash: rc.flash, cartCount }), status);
}
const unavailable = (rc, status = 503) =>
  page(rc, {
    title: 'Temporarily unavailable',
    body: `<div class="card"><p>The database is not answering right now. Nothing has been lost: the site itself is running, and pages
           that were viewed recently still load from a saved copy. Please try again in a minute.</p><p><a class="btn" href="">Try again</a></p></div>`,
  }, status);

async function loadContext(request, env, ctx) {
  const url = new URL(request.url);
  const cookies = parseCookies(request.headers.get('cookie'));
  const rc = { request, env, ctx, url, setCookies: [], user: null, cart: {}, flash: null };
  const secret = env.SESSION_SECRET;
  const s = await verifyToken(cookies.session, secret);
  if (s && s.uid) rc.user = { id: s.uid, name: s.name, role: s.role };
  const c = await verifyToken(cookies.cart, secret);
  if (c && c.items) rc.cart = c.items;
  if (cookies.flash) {
    const [kind, ...rest] = decodeURIComponent(cookies.flash).split(':');
    rc.flash = { kind: ['ok', 'err', 'warn'].includes(kind) ? kind : 'ok', text: rest.join(':') };
    rc.setCookies.push(cookie('flash', '', 0));
  }
  return rc;
}
async function saveCart(rc) {
  rc.setCookies.push(cookie('cart', await signToken({ items: rc.cart, exp: Date.now() + 7 * 86400e3 }, rc.env.SESSION_SECRET), 7 * 86400));
}
const requireRole = (rc, ...roles) => (rc.user && roles.includes(rc.user.role) ? null : rc.user ? 'forbidden' : 'login');
const denied = (rc, why) => (why === 'login' ? redirect(rc, '/login', { kind: 'warn', text: 'Please log in first.' })
  : page(rc, { title: 'Not allowed', body: '<p>Your account does not have access to this page.</p>' }, 403));
const intOf = (v, min = 1, max = 1e9) => { const n = Number.parseInt(v, 10); return Number.isInteger(n) && n >= min && n <= max ? n : null; };

// ------------------------------------------------------------------ pages
async function home(rc) {
  const { data, stale, ts } = await cached(rc, 'catalogue', () => withDb(rc, loadCatalogue), 600);
  const q = (rc.url.searchParams.get('q') || '').trim().toLowerCase();
  const cat = rc.url.searchParams.get('cat') || '';
  const cats = [...new Set(data.map((p) => p.category))];
  const list = data.filter((p) => (!q || p.name.toLowerCase().includes(q) || p.category.toLowerCase().includes(q)) && (!cat || p.category === cat));
  const canBuy = rc.user && rc.user.role === 'customer';
  const trs = list.map((p) => {
    const out = num(p.stock_quantity) <= 0;
    const buy = canBuy
      ? `<form method="post" action="/cart/add" class="inline"><input type="hidden" name="product_id" value="${esc(p.product_id)}">
         <input type="number" name="qty" value="1" min="1" max="${Math.max(1, num(p.stock_quantity))}" aria-label="Quantity"><button ${out || stale ? 'disabled' : ''}>Add</button></form>`
      : rc.user ? '<span class="muted">Customers only</span>' : '<a href="/login">Log in to buy</a>';
    return `<tr><td>${esc(p.name)}</td><td>${esc(p.category)}</td><td class="r">${money(p.price)}</td>
      <td class="r ${num(p.stock_quantity) <= num(p.reorder_level) ? 'stock-low' : ''}">${out ? 'Out of stock' : esc(p.stock_quantity)}</td>
      <td>${p.reviews ? esc(p.avg_rating) + ' (' + esc(p.reviews) + ')' : '<span class="muted">no reviews</span>'}</td><td>${buy}</td></tr>`;
  });
  const body = `<form method="get" class="row"><input type="search" name="q" value="${esc(rc.url.searchParams.get('q') || '')}" placeholder="Search products" aria-label="Search">
    <select name="cat" aria-label="Category"><option value="">All categories</option>${cats.map((c) => `<option ${c === cat ? 'selected' : ''}>${esc(c)}</option>`).join('')}</select>
    <button>Search</button></form>` + table(['Product', 'Category', 'Price', 'In stock', 'Rating', ''], trs, 'No product matches your search.');
  return page(rc, { title: 'Price list', body, stale: stale ? { ts } : null });
}

function loginPage(rc, error) {
  const demo = rc.env.SHOW_DEMO_LOGINS === 'false' ? '' : `<div class="card demo"><strong>Demo accounts</strong> (password <code>Demo#2026</code>)<br>
    Customer: <code>bwalya.chilufya3@example.com</code><br>Admin: <code>mwila.zulu1@example.com</code><br>Analyst: <code>chanda.phiri2@example.com</code></div>`;
  return page(rc, {
    title: 'Log in',
    body: `${error ? `<div class="flash err">${esc(error)}</div>` : ''}<form method="post" action="/login" class="card">
      <label for="email">Email</label><input id="email" type="email" name="email" required autocomplete="username">
      <label for="pw">Password</label><input id="pw" type="password" name="password" required autocomplete="current-password">
      <p><button>Log in</button></p></form>${demo}`,
  });
}

async function doLogin(rc, form) {
  const email = String(form.get('email') || '').trim().toLowerCase();
  const password = String(form.get('password') || '');
  if (!rc.env.SESSION_SECRET) return loginPage(rc, 'The site is not configured yet (SESSION_SECRET is missing).');
  const [u] = await withDb(rc, (c) => rows(c, `SELECT customer_id, first_name, last_name, password_hash, role FROM customers WHERE email = ?`, [email]));
  const ok = await verifyPassword(password, u ? u.password_hash : DUMMY_HASH);
  if (!u || !ok) return loginPage(rc, 'Wrong email or password.');
  const token = await signToken({ uid: u.customer_id, name: u.first_name + ' ' + u.last_name, role: u.role, exp: Date.now() + SESSION_HOURS * 3600e3 }, rc.env.SESSION_SECRET);
  rc.setCookies.push(cookie('session', token, SESSION_HOURS * 3600));
  const dest = u.role === 'admin' ? '/admin/orders' : u.role === 'analyst' ? '/reports' : '/';
  return redirect(rc, dest, { kind: 'ok', text: `Welcome, ${u.first_name}.` });
}

async function cartAdd(rc, form) {
  const why = requireRole(rc, 'customer'); if (why) return denied(rc, why);
  const pid = intOf(form.get('product_id')), qty = intOf(form.get('qty'), 1, 50);
  if (!pid || !qty) return redirect(rc, '/', { kind: 'err', text: 'Choose a quantity between 1 and 50.' });
  rc.cart[pid] = Math.min(50, (rc.cart[pid] || 0) + qty);
  await saveCart(rc);
  return redirect(rc, '/cart', { kind: 'ok', text: 'Added to your cart.' });
}
async function cartSet(rc, form) {
  const why = requireRole(rc, 'customer'); if (why) return denied(rc, why);
  const pid = intOf(form.get('product_id')), qty = intOf(form.get('qty'), 0, 50);
  if (pid && qty !== null) { if (qty === 0) delete rc.cart[pid]; else rc.cart[pid] = qty; }
  await saveCart(rc);
  return redirect(rc, '/cart');
}

const cartLines = (rc, conn) => {
  const ids = Object.keys(rc.cart).map(Number).filter(Boolean);
  return ids.length ? rows(conn, `SELECT product_id, name, price, stock_quantity FROM products WHERE is_active AND product_id IN (?)`, [ids]) : Promise.resolve([]);
};

async function cartPage(rc) {
  const why = requireRole(rc, 'customer'); if (why) return denied(rc, why);
  const lines = await withDb(rc, (c) => cartLines(rc, c));
  let total = 0;
  const trs = lines.map((p) => {
    const q = rc.cart[p.product_id]; total += q * num(p.price);
    return `<tr><td>${esc(p.name)}</td><td class="r">${money(p.price)}</td>
      <td><form method="post" action="/cart/set" class="inline"><input type="hidden" name="product_id" value="${esc(p.product_id)}">
      <input type="number" name="qty" value="${q}" min="0" max="50" aria-label="Quantity"><button class="secondary">Update</button></form></td>
      <td class="r">${money(q * num(p.price))}</td></tr>`;
  });
  const body = table(['Product', 'Price', 'Quantity (0 removes)', 'Line total'], trs, 'Your cart is empty.')
    + (lines.length ? `<p class="row"><strong>Total ${money(total)}</strong> <a class="btn" href="/checkout">Checkout</a></p>` : '');
  return page(rc, { title: 'Your cart', body });
}

async function checkoutPage(rc) {
  const why = requireRole(rc, 'customer'); if (why) return denied(rc, why);
  const { lines, addrs } = await withDb(rc, async (c) => ({
    lines: await cartLines(rc, c),
    addrs: await rows(c, `SELECT address_id, street, city, is_default FROM addresses WHERE customer_id = ? ORDER BY is_default DESC, address_id`, [rc.user.id]),
  }));
  if (!lines.length) return redirect(rc, '/cart', { kind: 'warn', text: 'Your cart is empty.' });
  if (!addrs.length) return page(rc, { title: 'Checkout', body: '<p>You have no delivery address on file.</p>' });
  const total = lines.reduce((s, p) => s + rc.cart[p.product_id] * num(p.price), 0);
  const body = `<p>${lines.length} item(s), total <strong>${money(total)}</strong>. Prices are fixed when the order is placed.</p>
    <form method="post" action="/checkout" class="card">
      <label for="addr">Delivery address</label><select id="addr" name="address_id">${addrs.map((a) => `<option value="${esc(a.address_id)}">${esc(a.street)}, ${esc(a.city)}</option>`).join('')}</select>
      <label for="m">Payment method</label><select id="m" name="method">${Object.entries(METHODS).map(([k, v]) => `<option value="${k}">${v}</option>`).join('')}</select>
      <label><input type="checkbox" name="fail" value="1"> Demo: make this payment fail</label>
      <p><button>Place order and pay</button></p></form>`;
  return page(rc, { title: 'Checkout', body });
}

async function doCheckout(rc, form) {
  const why = requireRole(rc, 'customer'); if (why) return denied(rc, why);
  const addr = intOf(form.get('address_id')), method = String(form.get('method'));
  const items = Object.entries(rc.cart).map(([pid, q]) => ({ product_id: Number(pid), quantity: q }));
  if (!items.length || !addr || !METHODS[method]) return redirect(rc, '/cart', { kind: 'err', text: 'Your order could not be read. Please try again.' });
  try {
    const result = await withDb(rc, async (c) => {
      const [{ order_id }] = await callRows(c, 'CALL place_order_rs(?, ?, ?)', [rc.user.id, addr, JSON.stringify(items)]);
      await c.query('CALL pay_order(?, ?, ?)', [order_id, method, form.get('fail') ? 0 : 1]);
      return order_id;
    });
    rc.cart = {}; await saveCart(rc);
    const failed = !!form.get('fail');
    return redirect(rc, '/orders', failed
      ? { kind: 'warn', text: `Order #${result} was saved but the payment failed. You can pay again below.` }
      : { kind: 'ok', text: `Order #${result} placed and paid.` });
  } catch (e) {
    if (isRuleError(e)) return redirect(rc, '/cart', { kind: 'err', text: ruleMessage(e) });
    throw e;
  }
}

async function ordersPage(rc) {
  const why = requireRole(rc, 'customer'); if (why) return denied(rc, why);
  const orders = await withDb(rc, (c) => rows(c, `
    SELECT o.order_id, o.order_date, o.status, o.total_amount,
           GROUP_CONCAT(CONCAT(p.name, ' x', i.quantity) ORDER BY p.name SEPARATOR ', ') AS items
      FROM orders o JOIN order_items i ON i.order_id = o.order_id JOIN products p ON p.product_id = i.product_id
     WHERE o.customer_id = ? AND o.status <> 'cart'
     GROUP BY o.order_id, o.order_date, o.status, o.total_amount ORDER BY o.order_id DESC LIMIT 50`, [rc.user.id]));
  const trs = orders.map((o) => {
    const act = o.status === 'placed'
      ? `<form method="post" action="/orders/${esc(o.order_id)}/pay" class="inline"><select name="method" aria-label="Method">${Object.entries(METHODS).map(([k, v]) => `<option value="${k}">${v}</option>`).join('')}</select><button>Pay</button></form>
         <form method="post" action="/orders/${esc(o.order_id)}/cancel" class="inline"><button class="secondary">Cancel</button></form>` : '';
    return `<tr><td>#${esc(o.order_id)}</td><td>${esc(shortDate(o.order_date))}</td><td><span class="tag">${esc(o.status)}</span></td><td>${esc(o.items)}</td><td class="r">${money(o.total_amount)}</td><td>${act}</td></tr>`;
  });
  return page(rc, { title: 'My orders', body: table(['Order', 'Date', 'Status', 'Items', 'Total', ''], trs, 'You have not placed an order yet.') });
}

// Customer actions on their own order. The ownership check is here; the state rules are in the database.
async function ownOrderAction(rc, form, orderId, action) {
  const why = requireRole(rc, 'customer'); if (why) return denied(rc, why);
  try {
    await withDb(rc, async (c) => {
      const [o] = await rows(c, 'SELECT customer_id FROM orders WHERE order_id = ?', [orderId]);
      if (!o || o.customer_id !== rc.user.id) { const e = new Error('That order is not yours.'); e.sqlState = '45000'; throw e; }
      if (action === 'cancel') await c.query('CALL cancel_order(?)', [orderId]);
      else { const m = String(form.get('method')); if (!METHODS[m]) throw Object.assign(new Error('Choose a payment method.'), { sqlState: '45000' }); await c.query('CALL pay_order(?, ?, 1)', [orderId, m]); }
    });
    return redirect(rc, '/orders', { kind: 'ok', text: action === 'cancel' ? `Order #${orderId} cancelled.` : `Order #${orderId} paid.` });
  } catch (e) {
    if (isRuleError(e)) return redirect(rc, '/orders', { kind: 'err', text: ruleMessage(e) });
    throw e;
  }
}

async function adminOrders(rc) {
  const why = requireRole(rc, 'admin'); if (why) return denied(rc, why);
  const status = rc.url.searchParams.get('status') || '';
  const orders = await withDb(rc, (c) => rows(c, `
    SELECT o.order_id, o.order_date, o.status, o.total_amount, CONCAT(cu.first_name, ' ', cu.last_name) AS customer, a.city
      FROM orders o JOIN customers cu ON cu.customer_id = o.customer_id LEFT JOIN addresses a ON a.address_id = o.address_id
     WHERE o.status <> 'cart' AND (? = '' OR o.status = ?) ORDER BY o.order_id DESC LIMIT 100`, [status, status]));
  const btn = (id, action, label, cls = '') => `<form method="post" action="/admin/orders/${esc(id)}/${action}" class="inline"><button class="${cls}">${label}</button></form>`;
  const trs = orders.map((o) => {
    const acts = [];
    if (o.status === 'paid') acts.push(btn(o.order_id, 'ship', 'Mark shipped'));
    if (o.status === 'shipped') acts.push(btn(o.order_id, 'deliver', 'Mark delivered'));
    if (['paid', 'shipped', 'delivered'].includes(o.status)) acts.push(btn(o.order_id, 'refund', 'Refund', 'secondary'));
    if (o.status === 'placed') acts.push(btn(o.order_id, 'cancel', 'Cancel', 'secondary'));
    return `<tr><td>#${esc(o.order_id)}</td><td>${esc(shortDate(o.order_date))}</td><td>${esc(o.customer)}</td><td>${esc(o.city || '')}</td><td><span class="tag">${esc(o.status)}</span></td><td class="r">${money(o.total_amount)}</td><td>${acts.join(' ')}</td></tr>`;
  });
  const filter = `<form method="get" class="row"><select name="status" aria-label="Status"><option value="">All statuses</option>${['placed', 'paid', 'shipped', 'delivered', 'cancelled', 'refunded'].map((s) => `<option ${s === status ? 'selected' : ''}>${s}</option>`).join('')}</select><button>Filter</button></form>`;
  return page(rc, { title: 'Orders', body: filter + table(['Order', 'Date', 'Customer', 'City', 'Status', 'Total', 'Actions'], trs, 'No orders.') });
}
async function adminOrderAction(rc, orderId, action) {
  const why = requireRole(rc, 'admin'); if (why) return denied(rc, why);
  try {
    await withDb(rc, async (c) => {
      if (action === 'refund') await c.query('CALL refund_order(?)', [orderId]);
      else if (action === 'cancel') await c.query('CALL cancel_order(?)', [orderId]);
      else if (action === 'ship') await c.query(`UPDATE orders SET status = 'shipped' WHERE order_id = ?`, [orderId]);
      else if (action === 'deliver') await c.query(`UPDATE orders SET status = 'delivered' WHERE order_id = ?`, [orderId]);
      else throw Object.assign(new Error('Unknown action.'), { sqlState: '45000' });
    });
    return redirect(rc, '/admin/orders', { kind: 'ok', text: `Order #${orderId}: ${action} done.` });
  } catch (e) {
    if (isRuleError(e)) return redirect(rc, '/admin/orders', { kind: 'err', text: ruleMessage(e) });
    throw e;
  }
}

async function adminStock(rc) {
  const why = requireRole(rc, 'admin'); if (why) return denied(rc, why);
  const { data, stale, ts } = await cached(rc, 'catalogue', () => withDb(rc, loadCatalogue), 600);
  const trs = [...data].sort((a, b) => (num(a.stock_quantity) - num(a.reorder_level)) - (num(b.stock_quantity) - num(b.reorder_level))).map((p) => {
    const low = num(p.stock_quantity) <= num(p.reorder_level);
    return `<tr><td>${esc(p.name)}</td><td>${esc(p.category)}</td><td class="r ${low ? 'stock-low' : ''}">${esc(p.stock_quantity)}</td><td class="r">${esc(p.reorder_level)}</td><td>${low ? '<span class="tag low">Reorder</span>' : ''}</td></tr>`;
  });
  return page(rc, { title: 'Stock levels', body: table(['Product', 'Category', 'In stock', 'Reorder level', ''], trs), stale: stale ? { ts } : null });
}

async function adminAudit(rc) {
  const why = requireRole(rc, 'admin'); if (why) return denied(rc, why);
  const list = await withDb(rc, (c) => rows(c, `SELECT audit_id, table_name, record_id, action, changed_by, changed_at, new_value FROM audit_log ORDER BY audit_id DESC LIMIT 100`));
  const trs = list.map((a) => `<tr><td>${esc(a.audit_id)}</td><td>${esc(a.changed_at)}</td><td>${esc(a.table_name)} #${esc(a.record_id)}</td><td>${esc(a.action)}</td><td>${esc(a.changed_by)}</td><td class="muted">${esc(String(a.new_value ?? '').slice(0, 90))}</td></tr>`);
  return page(rc, { title: 'Audit log', body: '<p class="muted">Written by database triggers on every change to orders, payments, and product price or stock. The web app cannot edit it.</p>' + table(['#', 'When', 'Record', 'Action', 'By', 'New value'], trs, 'No entries.') });
}

async function reportsPage(rc) {
  const why = requireRole(rc, 'admin', 'analyst'); if (why) return denied(rc, why);
  const { data: r, stale, ts } = await cached(rc, 'reports', () => withDb(rc, loadReports), 300);
  const avg = num(r.kpi.orders) ? num(r.kpi.revenue) / num(r.kpi.orders) : 0;
  const kpi = `<div class="row"><div class="card"><div class="muted">Revenue</div><strong>${money(r.kpi.revenue)}</strong></div>
    <div class="card"><div class="muted">Paid orders</div><strong>${esc(r.kpi.orders)}</strong></div>
    <div class="card"><div class="muted">Average order</div><strong>${money(avg)}</strong></div>
    <div class="card"><div class="muted">Buying customers</div><strong>${esc(r.kpi.customers)}</strong></div></div>`;
  const body = kpi + `<div class="grid2">
    <div class="card"><h2>Monthly revenue</h2>${lineChart(r.monthly.map((m) => ({ label: m.month, value: m.revenue })), { title: 'Monthly revenue' })}<p class="muted">Revenue counts orders that are paid, shipped or delivered.</p></div>
    <div class="card"><h2>Top 10 products by revenue</h2>${barChart(r.topProducts.map((p) => ({ label: p.name, value: p.revenue })), { title: 'Top products' })}</div>
    <div class="card"><h2>Revenue by city</h2>${barChart(r.city.map((c) => ({ label: c.city, value: c.revenue })), { title: 'Revenue by city' })}</div>
    <div class="card"><h2>Payment methods</h2>${table(['Method', 'Attempts', 'Share %', 'Failure %'], r.payments.map((p) => `<tr><td>${esc(METHODS[p.method] || p.method)}</td><td class="r">${esc(p.attempts)}</td><td class="r">${esc(p.share_pct)}</td><td class="r">${esc(p.failure_rate_pct)}</td></tr>`))}</div>
    <div class="card"><h2>Order status</h2>${barChart(r.funnel.map((f) => ({ label: f.status, value: f.orders })), { format: (v) => String(v), title: 'Order status' })}</div>
    <div class="card"><h2>Low stock</h2>${table(['Product', 'In stock', 'Reorder level'], r.lowStock.map((p) => `<tr><td>${esc(p.name)}</td><td class="r stock-low">${esc(p.stock_quantity)}</td><td class="r">${esc(p.reorder_level)}</td></tr>`), 'Nothing is low.')}</div></div>`;
  return page(rc, { title: 'Reports', body, stale: stale ? { ts } : null });
}

async function health(rc) {
  const t0 = Date.now();
  let db = 'up', error;
  try { await withDb(rc, (c) => c.query('SELECT 1')); } catch (e) { db = 'down'; error = e.code || e.message; }
  const strict = rc.url.searchParams.has('strict');
  return new Response(JSON.stringify({ site: 'ok', database: db, ms: Date.now() - t0, ...(error ? { error } : {}) }),
    { status: strict && db === 'down' ? 503 : 200, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });
}

// ------------------------------------------------------------------ router
async function route(rc) {
  const { request, url } = rc;
  const path = url.pathname.replace(/\/+$/, '') || '/';
  const method = request.method;
  if (path === '/health') return health(rc);

  if (method === 'GET' || method === 'HEAD') {
    if (path === '/') return home(rc);
    if (path === '/login') return rc.user ? redirect(rc, '/') : loginPage(rc);
    if (path === '/cart') return cartPage(rc);
    if (path === '/checkout') return checkoutPage(rc);
    if (path === '/orders') return ordersPage(rc);
    if (path === '/reports') return reportsPage(rc);
    if (path === '/admin/orders') return adminOrders(rc);
    if (path === '/admin/stock') return adminStock(rc);
    if (path === '/admin/audit') return adminAudit(rc);
    return page(rc, { title: 'Page not found', body: '<p><a href="/">Back to the shop</a></p>' }, 404);
  }

  if (method === 'POST') {
    const origin = request.headers.get('origin');                       // refuse form posts coming from other sites
    if (origin && origin !== url.origin) return new Response('Bad origin', { status: 403 });
    const form = await request.formData();
    if (path === '/login') return doLogin(rc, form);
    if (path === '/logout') { rc.setCookies.push(cookie('session', '', 0), cookie('cart', '', 0)); return redirect(rc, '/', { kind: 'ok', text: 'You are logged out.' }); }
    if (path === '/cart/add') return cartAdd(rc, form);
    if (path === '/cart/set') return cartSet(rc, form);
    if (path === '/checkout') return doCheckout(rc, form);
    let m;
    if ((m = path.match(/^\/orders\/(\d+)\/(pay|cancel)$/))) return ownOrderAction(rc, form, Number(m[1]), m[2]);
    if ((m = path.match(/^\/admin\/orders\/(\d+)\/(ship|deliver|refund|cancel)$/))) return adminOrderAction(rc, Number(m[1]), m[2]);
  }
  return new Response('Not found', { status: 404 });
}

export default {
  async fetch(request, env, ctx) {
    const rc = await loadContext(request, env, ctx);
    try {
      return await route(rc);
    } catch (e) {
      console.error('request failed', request.method, rc.url.pathname, e && (e.code || e.message));
      return unavailable(rc);          // the site stays up and explains; cached pages never reach this line
    }
  },

  // Runs every 30 minutes (wrangler.toml): proves the database answers, keeps it awake, refreshes the saved copies, raises an alert on failure.
  async scheduled(event, env, ctx) {
    const rc = { env, ctx };
    try {
      await withDb(rc, async (c) => {
        await c.query('SELECT 1');
        if (env.CACHE) {
          await env.CACHE.put('catalogue', JSON.stringify({ ts: Date.now(), data: await loadCatalogue(c) }), { expirationTtl: 1209600 });
          await env.CACHE.put('reports', JSON.stringify({ ts: Date.now(), data: await loadReports(c) }), { expirationTtl: 1209600 });
        }
      });
      console.log('health check ok');
    } catch (e) {
      console.error('health check FAILED', e && (e.code || e.message));
      if (env.ALERT_WEBHOOK_URL) {
        ctx.waitUntil(fetch(env.ALERT_WEBHOOK_URL, { method: 'POST', body: `${env.SHOP_NAME || 'Shop'}: database check failed (${e && (e.code || e.message)})` }).catch(() => {}));
      }
    }
  },
};
