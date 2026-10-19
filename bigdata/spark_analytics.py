"""Stage 7 step 3: PySpark prototype. Runs locally (no cluster needed); the same code runs unchanged on a cluster.
  1. Read the CSV export and the clickstream JSON lines.
  2. Write the raw clickstream as date-partitioned Parquet  (data lake, 'bronze' layer).
  3. Reproduce Stage 4 queries Q1 (top products) and Q3 (monthly revenue) with Spark; verify_match.py compares them to PostgreSQL.
  4. New analytics SQL cannot do on this schema: clickstream funnel and search terms (written as 'gold' tables).
  5. Show partition pruning: a one-day query only reads one partition.
Run:  python3 bigdata/spark_analytics.py"""
import os, shutil, glob
from pyspark.sql import SparkSession, functions as F, Window

HERE = os.path.dirname(os.path.abspath(__file__)); DATA = f"{HERE}/data"; OUT = f"{HERE}/out"
spark = (SparkSession.builder.master("local[*]").appName("ecommerce-bigdata-prototype")
         .config("spark.sql.shuffle.partitions", "8").config("spark.ui.showConsoleProgress", "false").getOrCreate())
spark.sparkContext.setLogLevel("ERROR")
csv = lambda n: spark.read.csv(f"{DATA}/csv/{n}.csv", header=True, inferSchema=True)
orders, items, products = csv("orders"), csv("order_items"), csv("products")
REV = ["paid", "shipped", "delivered"]

def save_csv(df, name):                       # one small CSV per result, for comparison and for the report
    df.toPandas().to_csv(f"{OUT}/{name}.csv", index=False)

shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT)

# ---- 2. bronze: raw clickstream -> Parquet partitioned by date ----
clicks = (spark.read.json(f"{DATA}/clickstream.jsonl")
          .withColumn("ts", F.to_timestamp("ts")).withColumn("event_date", F.to_date("ts")))
clicks.write.mode("overwrite").partitionBy("event_date").parquet(f"{OUT}/parquet/clickstream_raw")
bronze = spark.read.parquet(f"{OUT}/parquet/clickstream_raw")
print("clickstream events:", bronze.count(), "| partitions (days):", bronze.select("event_date").distinct().count())

# ---- 3. Q1 and Q3 in Spark ----
paid = orders.filter(F.col("status").isin(REV))
q1 = (items.join(paid, "order_id").join(products.select("product_id", "name"), "product_id")
      .groupBy("name").agg(F.sum("quantity").alias("units_sold"),
                           F.round(F.sum(F.col("quantity") * F.col("unit_price")), 2).alias("revenue"))
      .orderBy(F.desc("revenue")))
save_csv(q1, "q1_top_products")
q3 = (paid.groupBy(F.date_trunc("month", "order_date").cast("date").alias("month"))
      .agg(F.round(F.sum("total_amount"), 2).alias("revenue")).orderBy("month"))
w = Window.orderBy("month")
q3 = q3.withColumn("previous_month", F.lag("revenue").over(w)) \
       .withColumn("growth_pct", F.round(100 * (F.col("revenue") - F.col("previous_month")) / F.col("previous_month"), 1))
save_csv(q3, "q3_monthly_revenue")

# ---- 4. gold tables: things the relational schema cannot answer ----
funnel = (bronze.filter(F.col("event_type").isin("product_view", "add_to_cart", "checkout_start", "purchase"))
          .groupBy("event_type").agg(F.countDistinct("session_id").alias("sessions")))
order = {"product_view": 1, "add_to_cart": 2, "checkout_start": 3, "purchase": 4}
fp = funnel.toPandas(); fp["step"] = fp.event_type.map(order); fp = fp.sort_values("step")
fp["pct_of_viewers"] = (100 * fp.sessions / fp.sessions.iloc[0]).round(1); fp.drop(columns="step").to_csv(f"{OUT}/gold_funnel.csv", index=False)

per_prod = (bronze.filter(F.col("product_id").isNotNull())
            .groupBy("product_id").pivot("event_type", ["product_view", "add_to_cart", "purchase"]).count().na.fill(0)
            .join(products.select("product_id", "name", "stock_quantity"), "product_id")
            .withColumn("view_to_purchase_pct", F.round(100 * F.col("purchase") / F.col("product_view"), 1))
            .orderBy(F.desc("product_view")))
save_csv(per_prod, "gold_product_conversion")
per_prod.write.mode("overwrite").parquet(f"{OUT}/parquet/gold_product_conversion")

daily = bronze.groupBy("event_date", "event_type").count()
daily.write.mode("overwrite").partitionBy("event_date").parquet(f"{OUT}/parquet/gold_daily_events")
save_csv(bronze.filter("event_type='search'").groupBy("search_term").count().orderBy(F.desc("count")).limit(10), "gold_top_searches")
save_csv(bronze.filter("event_type='product_view'").groupBy("city").agg(F.countDistinct("session_id").alias("sessions")).orderBy(F.desc("sessions")), "gold_sessions_by_city")

# ---- 5. partition pruning evidence ----
day = bronze.agg(F.min("event_date")).first()[0].isoformat()
one = spark.read.parquet(f"{OUT}/parquet/clickstream_raw").filter(F.col("event_date") == day)
plan = one._jdf.queryExecution().executedPlan().toString()
import re; m = re.search(r"PartitionFilters: \[.*?\](?=, PushedFilters)", plan); pf = m.group(0) if m else "n/a"
with open(f"{OUT}/partition_pruning.txt", "w") as f:
    f.write(f"Query: events on {day} only\nPhysical plan shows -> {pf}\nPartitions on disk: {bronze.select("event_date").distinct().count()}; this query reads 1 of them\nrows returned: {one.count()}\n")
print(open(f"{OUT}/partition_pruning.txt").read())

# ---- sizes: CSV/JSON vs Parquet ----
def size(pattern): return sum(os.path.getsize(p) for p in glob.glob(pattern, recursive=True) if os.path.isfile(p))
js = os.path.getsize(f"{DATA}/clickstream.jsonl"); pq = size(f"{OUT}/parquet/clickstream_raw/**/*")
nfiles = len([p for p in glob.glob(f"{OUT}/parquet/clickstream_raw/**/*.parquet", recursive=True)])
with open(f"{OUT}/storage_sizes.txt", "w") as f:
    f.write(f"clickstream.jsonl: {js:,} bytes\nParquet (snappy, partitioned by date): {pq:,} bytes in {nfiles} files\nParquet is {100*pq/js:.0f}% of the JSON size\n")
print(open(f"{OUT}/storage_sizes.txt").read())
spark.stop()
