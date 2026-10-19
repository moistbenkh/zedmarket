"""Stage 7 step 1: batch export from MySQL to CSV (the 'ingestion' hop of the architecture).
Personal data is dropped at the door: no names, emails, phones or password hashes leave the database.
Run:  python3 bigdata/export_to_csv.py        (needs pymysql; connection settings come from the DB_* environment variables)"""
import csv, os
from db import connect

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data", "csv")
os.makedirs(OUT, exist_ok=True)

EXPORTS = {
    "orders":      "SELECT order_id, customer_id, address_id, order_date, status, total_amount FROM orders ORDER BY order_id",
    "order_items": "SELECT order_item_id, order_id, product_id, quantity, unit_price FROM order_items ORDER BY order_item_id",
    "products":    "SELECT p.product_id, p.name, p.sku, p.price, p.stock_quantity, p.category_id, c.name AS category FROM products p JOIN categories c ON c.category_id = p.category_id ORDER BY p.product_id",
    "payments":    "SELECT payment_id, order_id, method, status, amount, paid_at FROM payments ORDER BY payment_id",
    "customers":   "SELECT c.customer_id, c.registered_at, a.city, a.province FROM customers c LEFT JOIN addresses a ON a.customer_id = c.customer_id AND a.is_default ORDER BY c.customer_id",
}

con = connect()
try:
    with con.cursor() as cur:
        for name, sql in EXPORTS.items():
            cur.execute(sql)
            cols = [d[0] for d in cur.description]
            n = 0
            with open(os.path.join(OUT, name + ".csv"), "w", newline="") as f:
                w = csv.writer(f)
                w.writerow(cols)
                for row in cur:
                    w.writerow(["" if v is None else v for v in row]); n += 1
            print(f"{name:12s} {n:6d} rows -> data/csv/{name}.csv")
finally:
    con.close()
