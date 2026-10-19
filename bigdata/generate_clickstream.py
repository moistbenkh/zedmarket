"""Stage 7 step 2: synthetic clickstream (page views, searches, product views, cart, checkout, purchase).
The SQL database has no table for this, so it is generated as JSON lines, the way a web tracker would emit it.
Purchases are tied to REAL orders from the database export, so the funnel numbers can be cross-checked.
Run:  python3 bigdata/generate_clickstream.py [sessions]     (fixed random seed, repeatable)"""
import csv, json, os, random, sys, datetime as dt
from collections import defaultdict
random.seed(2026)
HERE = os.path.dirname(__file__); CSV = os.path.join(HERE, "data", "csv")
N_BROWSE = int(sys.argv[1]) if len(sys.argv) > 1 else 6000     # non-purchasing sessions

rd = lambda f: list(csv.DictReader(open(os.path.join(CSV, f))))
orders, items, products, customers = rd("orders.csv"), rd("order_items.csv"), rd("products.csv"), rd("customers.csv")
city_of = {c["customer_id"]: c["city"] or "Lusaka" for c in customers}
lines = defaultdict(list)
for i in items: lines[i["order_id"]].append(i["product_id"])
pids = [p["product_id"] for p in products]
# popularity weights = how often each product was bought (+1 so every product gets some views)
pop = defaultdict(int)
for i in items: pop[i["product_id"]] += int(i["quantity"])
weights = [pop[p] + 1 for p in pids]
terms = ["phone", "laptop", "charger", "earbuds", "dress", "maize meal", "cooking oil", "rice", "kettle", "jeans",
         "power bank", "speaker", "sandals", "pan set", "blender", "cheap phone", "school laptop", "sugar"]
devices = [("mobile", .68), ("desktop", .27), ("tablet", .05)]
cities = [("Lusaka", 30), ("Kitwe", 16), ("Ndola", 14), ("Livingstone", 8), ("Kabwe", 6), ("Chingola", 5), ("Solwezi", 4), ("Choma", 3), ("Mufulira", 3)]

events, sid = [], 0
def emit(sess, ts, etype, **kw):
    events.append({"event_id": len(events) + 1, "ts": ts.strftime("%Y-%m-%d %H:%M:%S"), "session_id": sess["id"],
                   "customer_id": sess["cust"], "device": sess["dev"], "city": sess["city"], "event_type": etype,
                   "product_id": int(kw["pid"]) if kw.get("pid") else None, "search_term": kw.get("term"), "quantity": kw.get("qty")})

def session(ts, cust=None, city=None, buy=None):
    """One visit. buy = list of product_ids that end in a purchase; otherwise the visitor browses and may abandon."""
    global sid; sid += 1
    s = {"id": f"S{sid:06d}", "cust": int(cust) if cust else (random.randint(3, 42) if random.random() < .45 else None),
         "dev": random.choices([d for d, _ in devices], [w for _, w in devices])[0],
         "city": city or random.choices([c for c, _ in cities], [w for _, w in cities])[0]}
    t = ts; step = lambda: dt.timedelta(seconds=random.randint(8, 120))
    emit(s, t, "page_view")
    if random.random() < .45 or buy: t += step(); emit(s, t, "search", term=random.choice(terms))
    viewed = list(buy or [])
    for _ in range(random.choices([1, 2, 3, 4, 5, 6], [30, 25, 20, 12, 8, 5])[0]):
        viewed.append(random.choices(pids, weights)[0])
    random.shuffle(viewed)
    for p in viewed: t += step(); emit(s, t, "product_view", pid=p)
    carted = list(buy or [])
    if not buy and random.random() < .14: carted = [random.choice(viewed)]
    for p in carted: t += step(); emit(s, t, "add_to_cart", pid=p, qty=1)
    if carted and (buy or random.random() < .45):
        t += step(); emit(s, t, "checkout_start")
        if buy:
            t += step()
            for p in buy: emit(s, t, "purchase", pid=p, qty=1)

# 1) one converting session per real order that was not abandoned as a bare cart
for o in orders:
    if o["status"] == "cart": continue
    od = dt.datetime.fromisoformat(o["order_date"])
    session(od - dt.timedelta(minutes=random.randint(6, 25)), cust=o["customer_id"], city=city_of.get(o["customer_id"]), buy=lines[o["order_id"]])

# 2) browsing sessions spread over the same 12 months, heavier in Nov-Dec (seasonal peak)
start, end = dt.datetime(2025, 10, 18), dt.datetime(2026, 10, 18)
days = [start + dt.timedelta(days=i) for i in range((end - start).days)]
dw = [2.2 if d.month in (11, 12) else 1.4 if d.month in (2, 8) else 1.0 for d in days]
for _ in range(N_BROWSE):
    d = random.choices(days, dw)[0]
    session(d + dt.timedelta(seconds=random.randint(6 * 3600, 23 * 3600)))

events.sort(key=lambda e: (e["ts"], e["event_id"]))
for n, e in enumerate(events, 1): e["event_id"] = n
path = os.path.join(HERE, "data", "clickstream.jsonl")
with open(path, "w") as f:
    for e in events: f.write(json.dumps(e) + "\n")
print(f"{len(events)} events, {sid} sessions -> {path}  ({os.path.getsize(path)/1e6:.1f} MB)")
