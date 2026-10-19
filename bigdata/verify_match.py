"""Stage 7 check: Spark results must equal the MySQL results (Stage 4 Q1 and Q3).
Run after spark_analytics.py:  python3 bigdata/verify_match.py      Exit code 0 = all match."""
import os, sys, csv
from db import connect
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
Q1 = """SELECT p.name, SUM(i.quantity), SUM(i.quantity*i.unit_price) FROM order_items i JOIN orders o ON o.order_id = i.order_id
        JOIN products p ON p.product_id = i.product_id WHERE o.status IN ('paid','shipped','delivered') GROUP BY p.name"""
Q3 = """SELECT DATE_FORMAT(order_date, '%Y-%m-01'), SUM(total_amount) FROM orders
        WHERE status IN ('paid','shipped','delivered') GROUP BY 1"""
def spark_rows(n): return list(csv.DictReader(open(f"{OUT}/{n}.csv")))
ok = True
con = connect()
try:
    with con.cursor() as cur:
        cur.execute(Q1); pg = {r[0]: (int(r[1]), float(r[2])) for r in cur.fetchall()}
        sp = {r["name"]: (int(r["units_sold"]), float(r["revenue"])) for r in spark_rows("q1_top_products")}
        bad = [k for k in pg if sp.get(k) != pg[k]]
        print(f"Q1 top products : {len(pg)} products in MySQL, {len(sp)} in Spark, mismatches: {len(bad)}"); ok &= not bad and len(pg) == len(sp)
        cur.execute(Q3); pg3 = {str(r[0]): float(r[1]) for r in cur.fetchall()}
        sp3 = {r["month"]: float(r["revenue"]) for r in spark_rows("q3_monthly_revenue")}
        bad3 = [k for k in pg3 if sp3.get(k) != pg3[k]]
        print(f"Q3 monthly rev. : {len(pg3)} months in MySQL, {len(sp3)} in Spark, mismatches: {len(bad3)}"); ok &= not bad3 and len(pg3) == len(sp3)
        purchases = sum(int(r["sessions"]) for r in spark_rows("gold_funnel") if r["event_type"] == "purchase")
        cur.execute("SELECT COUNT(*) FROM orders WHERE status <> 'cart'"); n_orders = cur.fetchone()[0]
        print(f"Purchase sessions in clickstream: {purchases}; non-cart orders in MySQL: {n_orders}"); ok &= purchases == n_orders
finally:
    con.close()
print("RESULT:", "ALL MATCH" if ok else "MISMATCH"); sys.exit(0 if ok else 1)
