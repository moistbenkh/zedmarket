# Scalability and the case for Big Data (Stage 7)

## 1. Where this project stands
The database holds 160 orders, 294 order lines and 157 payments. MySQL answers every one of the 15 queries instantly, and nothing here needs Big Data tools. The question is what happens when the shop grows, and which parts of the design survive.

## 2. What happens at millions and billions of records
The figures below are extrapolations from this project's own data (about 218 bytes per click event as JSON), not measurements. They show orders of magnitude, not exact sizes.

| Scale | Example | Click events as JSON | Same events as Parquet (about 28%, measured here) | What happens in a single MySQL server |
| --- | --- | --- | --- | --- |
| Today | 160 orders, 27 thousand events | 6 MB | 1.7 MB | Everything is instant. |
| Growth | 1 million orders, 100 million events | about 22 GB | about 6 GB | Still possible, but large scans take minutes and compete with checkout for CPU and disk. |
| Large | 100 million orders, 10 billion events | about 2 TB | about 600 GB | Reports scan tables far larger than memory. Indexes alone reach hundreds of GB. Backups and rebuilds take hours. |
| Very large | 1 billion order lines and 100 billion events | about 22 TB | about 6 TB | One machine cannot hold or scan this in useful time. |

## 3. Limits of a traditional SQL database
1. **One machine.** A relational database scales up (a bigger server) far more easily than out. There is a ceiling on disk, memory and CPU, and cost rises faster than capacity.
2. **Transactions and reports compete.** The same server must keep stock correct and answer "revenue by city". A long report holds resources that checkout needs.
3. **Row storage.** Rows are stored whole, so a query that needs two columns still reads every column. Analytics queries touch few columns across many rows, which is the opposite of what row storage is good at.
4. **Index cost.** Indexes speed up reads but slow down writes and take space. At billions of rows they become as large as the data.
5. **Rigid schema.** Click events, search terms and device logs change shape often. Forcing them into tables means constant schema changes, and no table exists for them in this design.
6. **Operations.** Backup, restore and schema changes grow from seconds to hours as data grows.

## 4. Why Big Data tools are needed
Big Data tools change how data is stored and how work is divided, rather than just adding hardware:
- **Distributed storage** (HDFS or object storage) splits files into blocks spread over many cheap machines, with copies for safety. Capacity grows by adding machines.
- **Parallel processing** (Spark) splits a job into tasks that run on many machines at once. Ten times the machines gives roughly a tenth of the time for scan-heavy work.
- **Schema-on-read.** Raw files are stored as they arrive and given structure when read, so new event types do not require migrations.
- **Separation of storage and compute.** Data sits cheaply in the lake; compute is started only when a job runs.

## 5. How data is stored and processed efficiently
Measured in the prototype:
- **Columnar, compressed storage.** The 27,155 events take 5.9 MB as JSON and 1.7 MB as Parquet, 28% of the size, and a query reads only the columns it names.
- **Partitioning by date.** A query for one day read 1 of 365 partition folders; Spark's physical plan shows the date filter being applied before any file is opened (`bigdata/out/partition_pruning.txt`).
- **Same code at any size.** The PySpark job ran in local mode here. On a cluster the code is unchanged; only the master setting differs.

Techniques used at scale that this prototype only describes: broadcast joins (ship a small table such as products to every worker so the large table is not shuffled), predicate pushdown, data skipping with file statistics, and compacting small files.

**A limit of this prototype worth stating.** Daily partitions gave 365 files for 27 thousand events, about 74 events per file. That is the "small files problem": too many tiny files slow down Spark. Daily partitioning is right at millions of events per day and wrong at this volume. In production the job would compact files or partition by month.

## 6. How the results support decisions
The prototype produces answers that managers act on. The clickstream is synthetic, so the figures show the method; the SQL results come from the seeded database.

| Question | Source | Result in this data | Decision it supports |
| --- | --- | --- | --- |
| Where do shoppers drop out? | Clickstream funnel (Spark) | Of 6,157 sessions, 16.4% add to cart, 8.5% start checkout, 2.5% buy | Focus on the cart-to-checkout and checkout-to-payment steps, for example simpler mobile money payment |
| Which products are being looked at but not bought? | Product conversion (Spark) | Among products with 150+ views, view-to-purchase conversion is about 1.3% to 2.5% | Review price, photos or stock for low-converting, high-view products |
| Is stock keeping up with demand? | Stage 4 Q7 and `v_low_stock` | 4 products are at or below their reorder level | Reorder before they sell out |
| Which regions matter? | Stage 4 Q5 and sessions by city | Kitwe has the highest revenue (ZMW 66,831), ahead of Choma and Ndola, although Lusaka has the most sessions | Plan delivery coverage and promotions per city |
| When is demand highest? | Stage 4 Q3 | Top months are Feb 2026, Dec 2025 and Nov 2025 | Buy stock and plan campaigns ahead of these months |

Total revenue in the period was ZMW 302,915 from orders in paid, shipped or delivered status.

## 7. What would change at scale (summary)
MySQL stays as the system of record for orders. Event data and historical analysis move to the lake. Spark builds curated tables, and a warehouse or Trino serves the dashboards. Only the query engine changes; the business questions in Stage 4 stay the same.
