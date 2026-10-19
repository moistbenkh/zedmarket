"""Builds the 3 charts from the CSV files exported from the database (see ../README.md)."""
import csv, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

def rows(f): return list(csv.DictReader(open(f"csv/{f}")))
C = ["#1f4e79", "#2e86c1", "#f39c12", "#c0392b"]

# 1. Monthly revenue (line)
m = rows("monthly_revenue.csv")
labels = [r["month"][:7] for r in m]; vals = [float(r["revenue"]) for r in m]
fig, ax = plt.subplots(figsize=(9, 4.5))
ax.plot(labels, vals, marker="o", color=C[0], lw=2)
ax.set_title("Monthly Revenue, Oct 2025 to Oct 2026"); ax.set_xlabel("Month (Oct 2026 is partial)"); ax.set_ylabel("Revenue (ZMW)")
ax.grid(alpha=.3); plt.xticks(rotation=45, ha="right")
ax.yaxis.set_major_formatter(matplotlib.ticker.FuncFormatter(lambda x, _: f"{x:,.0f}"))
for x, y in zip(labels, vals): ax.annotate(f"{y/1000:.1f}k", (x, y), textcoords="offset points", xytext=(0, 7), ha="center", fontsize=8)
plt.tight_layout(); plt.savefig("chart1_monthly_revenue.png", dpi=150); plt.close()

# 2. Revenue by top-level category (bar)
c = rows("revenue_by_top_category.csv")
fig, ax = plt.subplots(figsize=(8, 4.5))
bars = ax.bar([r["top_category"] for r in c], [float(r["revenue"]) for r in c], color=C[1])
ax.set_title("Revenue by Product Category"); ax.set_xlabel("Category"); ax.set_ylabel("Revenue (ZMW)")
ax.yaxis.set_major_formatter(matplotlib.ticker.FuncFormatter(lambda x, _: f"{x:,.0f}"))
ax.bar_label(bars, labels=[f"{float(r['revenue']):,.0f}" for r in c], padding=3, fontsize=9)
ax.grid(axis="y", alpha=.3); plt.tight_layout(); plt.savefig("chart2_revenue_by_category.png", dpi=150); plt.close()

# 3. Payment method share (donut)
p = rows("payment_methods.csv")
names = [r["method"].replace("_", " ").title() for r in p]; n = [int(r["payments"]) for r in p]
fig, ax = plt.subplots(figsize=(7, 5))
w, t, a = ax.pie(n, labels=names, colors=C, autopct="%1.1f%%", startangle=90, pctdistance=.78, wedgeprops=dict(width=.4, edgecolor="white"))
for x in a: x.set_color("white"); x.set_fontsize(9)
ax.set_title("Payment Method Share (all payment attempts, n=%d)" % sum(n))
plt.tight_layout(); plt.savefig("chart3_payment_share.png", dpi=150); plt.close()
