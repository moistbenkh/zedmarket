// ui.js : page layout and small SVG charts (drawn on the server, no JavaScript needed in the browser).
import { esc, money, num } from './util.js';

export function layout(rc, { title, body, user, flash, stale, cartCount = 0 }) {
  const shop = esc(rc.env.SHOP_NAME || 'Zed Market');
  const nav = [];
  nav.push(`<a href="/">Shop</a>`);
  if (user && user.role === 'customer') nav.push(`<a href="/cart">Cart${cartCount ? ` (${cartCount})` : ''}</a>`, `<a href="/orders">My orders</a>`);
  if (user && (user.role === 'admin' || user.role === 'analyst')) nav.push(`<a href="/reports">Reports</a>`);
  if (user && user.role === 'admin') nav.push(`<a href="/admin/orders">Orders</a>`, `<a href="/admin/stock">Stock</a>`, `<a href="/admin/audit">Audit log</a>`);
  const who = user
    ? `<form method="post" action="/logout" class="inline"><span class="who">${esc(user.name)} <em>${esc(user.role)}</em></span> <button class="link">Log out</button></form>`
    : `<a href="/login">Log in</a>`;
  const flashHtml = flash ? `<div class="flash ${esc(flash.kind)}" role="status">${esc(flash.text)}</div>` : '';
  const staleHtml = stale
    ? `<div class="flash warn" role="status">The database is not answering right now, so this page shows the last saved copy${stale.ts ? ' from ' + esc(new Date(stale.ts).toISOString().slice(0, 16).replace('T', ' ')) + ' UTC' : ''}. Orders are paused until it is back.</div>`
    : '';
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)} | ${shop}</title><link rel="stylesheet" href="/style.css"></head><body>
<header><a class="brand" href="/">${shop}</a><nav>${nav.join('')}</nav><div class="account">${who}</div></header>
<main><h1>${esc(title)}</h1>${flashHtml}${staleHtml}${body}</main>
<footer>E-Commerce Customer and Sales Analytics. Cloudflare Worker + Aiven MySQL. Fictional data.</footer></body></html>`;
}

export const table = (head, rowsHtml, empty = 'Nothing to show.') =>
  rowsHtml.length
    ? `<div class="scroll"><table><thead><tr>${head.map((h) => `<th>${esc(h)}</th>`).join('')}</tr></thead><tbody>${rowsHtml.join('')}</tbody></table></div>`
    : `<p class="muted">${esc(empty)}</p>`;

// Horizontal bars: items = [{label, value}]
export function barChart(items, { format = money, title = '' } = {}) {
  const data = items.map((d) => ({ label: String(d.label), value: num(d.value) }));
  if (!data.length) return '<p class="muted">No data.</p>';
  const max = Math.max(...data.map((d) => d.value), 1);
  const rowH = 26, labelW = 170, barW = 360, w = labelW + barW + 110, h = data.length * rowH + 8;
  const bars = data.map((d, i) => {
    const y = i * rowH + 4, bw = Math.max(1, (d.value / max) * barW);
    return `<text x="${labelW - 8}" y="${y + 16}" text-anchor="end" class="axis">${esc(d.label.length > 24 ? d.label.slice(0, 23) + '…' : d.label)}</text>
<rect x="${labelW}" y="${y + 3}" width="${bw.toFixed(1)}" height="${rowH - 9}" rx="3" class="bar"/>
<text x="${labelW + bw + 6}" y="${y + 16}" class="val">${esc(format(d.value))}</text>`;
  }).join('');
  return `<svg viewBox="0 0 ${w} ${h}" role="img" aria-label="${esc(title)}" class="chart">${bars}</svg>`;
}

// Line chart: points = [{label, value}]
export function lineChart(points, { title = '' } = {}) {
  const data = points.map((d) => ({ label: String(d.label), value: num(d.value) }));
  if (data.length < 2) return '<p class="muted">Not enough data.</p>';
  const W = 640, H = 250, L = 60, R = 16, T = 14, B = 34;
  const max = Math.max(...data.map((d) => d.value), 1);
  const x = (i) => L + (i * (W - L - R)) / (data.length - 1);
  const y = (v) => T + (1 - v / max) * (H - T - B);
  const path = data.map((d, i) => `${i ? 'L' : 'M'}${x(i).toFixed(1)},${y(d.value).toFixed(1)}`).join(' ');
  const grid = [0, 0.5, 1].map((f) => `<line x1="${L}" x2="${W - R}" y1="${y(max * f).toFixed(1)}" y2="${y(max * f).toFixed(1)}" class="grid"/><text x="${L - 6}" y="${(y(max * f) + 4).toFixed(1)}" text-anchor="end" class="axis">${Math.round((max * f) / 1000)}k</text>`).join('');
  const labels = data.map((d, i) => (i % 2 === 0 ? `<text x="${x(i).toFixed(1)}" y="${H - 12}" text-anchor="middle" class="axis">${esc(d.label.slice(2, 7))}</text>` : '')).join('');
  const dots = data.map((d, i) => `<circle cx="${x(i).toFixed(1)}" cy="${y(d.value).toFixed(1)}" r="3" class="dot"><title>${esc(d.label)}: ${esc(money(d.value))}</title></circle>`).join('');
  return `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="${esc(title)}" class="chart">${grid}<path d="${path}" class="line" fill="none"/>${dots}${labels}</svg>`;
}
