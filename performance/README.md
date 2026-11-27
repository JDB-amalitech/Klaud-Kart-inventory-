# Performance: before and after

- **Measured:** 2026-11-27, PostgreSQL 18.7 in Docker on an ordinary laptop (8 cores), full cleaned dataset (159,172 orders, 39,885 customers)
- **How:** `measure.sql` runs `EXPLAIN (ANALYZE, BUFFERS)` on every report query, once before `solution/05_indexes.sql` (`before.txt`) and once after (`after.txt`). The full plans are in those files.
- **Report date:** fixed at 2026-08-31, so runs are comparable.

| Query | Before indexes | After indexes | Budget |
|---|---|---|---|
| A. **Naive** Monday report: 14 lookups per customer, **200 customers only** | 44,078 ms | 12 ms | — |
| A, scaled to all 39,885 customers | **≈ 2 h 26 min** | ≈ 2.4 s | — |
| B. **Monday report, all customers, one pass** (`monday_report`) | **1,305 ms** | 1,525 ms | seconds ✅ |
| C. Top 100 | 1,090 ms | 1,041 ms | seconds ✅ |
| D. Running total, every counted order | 158 ms | 135 ms | seconds ✅ |
| E. Running total, one customer | 32.0 ms | **0.23 ms** | — |
| F. Low-stock rollup, whole tree | 8.1 ms | 7.2 ms | a couple of seconds ✅ |
| G. Stock trail, one product | 22.6 ms | **0.54 ms** | — |

## What the numbers say

1. **The slow report is a query-shape problem, not a hardware problem.** The naive version asks the same table the same question once per figure per customer: 39,885 customers × 14 lookups, each reading all 159k orders. That is about 2.4 hours here, which matches "40 minutes, and some Mondays it doesn't finish". The one-pass version reads the orders **once** and computes every figure together: 1.3 s, about **6,700× faster**, with no index at all. A bigger server would make the naive version perhaps 2× faster, so it would still take an hour or more.
2. **Indexes help the queries that look up one customer or one product, and correctly change nothing for the full report.**
   - The one-customer running total went from 32 ms to 0.23 ms (140×).
   - The one-product audit trail went from 22.6 ms to 0.54 ms (40×).
   - The full report reads every order anyway, so PostgreSQL rightly ignores the index. B varied 1.3–1.9 s across runs, which is run-to-run noise.
   - The index also rescues the naive version (2.4 s for everyone), which shows the original report was missing an index on `orders.customer_id`.
3. **Why no materialized view.** A stored copy would answer in milliseconds, but its figures would be stale until refreshed, and a plain refresh blocks readers. At 1.3 s the live report already meets the budget, so the staleness isn't worth it. Revisit if order volume grows about 10×.

## What the indexes cost

| Index | Size | Serves |
|---|---|---|
| `ix_orders_customer_date` | 10 MB | one customer's orders in date order (running total, lookups) |
| `ix_inventory_log_product_time` | 11 MB | one product's movements in time order (audit trail) |
| `ix_order_items_order` | 5.4 MB | joins from orders to lines; key checks when an order is deleted |
| `ix_order_items_product` | 2.3 MB | key checks when a product is deleted (race_test cleanup) |

Every sale writes to these. With all four in place, the race test's 400-buyer flash sale still completes in 3.7–4.0 s with no errors.

## Flash-sale measurements (`place_order`)

| Measure | Result |
|---|---|
| One sale, no contention, including its commit | 5.6 ms |
| 400 buyers, 50 units: queue on row lock only | 1,635 ms average per call (server), 5.2–5.9 s wall clock |
| 400 buyers, 50 units: **first-come-first-served queue, then row lock (shipped)** | **1,098 ms average per call (−33%), 3.7–4.0 s wall clock** |
| Race test, all four tests | passed in every one of 11 consecutive full runs |
