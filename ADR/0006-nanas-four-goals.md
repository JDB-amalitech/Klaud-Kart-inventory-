# 0006: How Nana's four goals are met

- **Status:** Accepted
- **Date:** 2026-11-27
- **Files:** `solution/01_audit_trail.sql` to `05_indexes.sql` (run by `solution/solution_all.sql`); evidence in `performance/README.md` and `validation/post_solution_*.txt`
- **Environment:** PostgreSQL 18 (the graded version) with `max_connections = 500`. The default of 100 refuses most of race_test's 400 buyers before they ever reach the function.

## Goal 1: No overselling (`place_order`)

**How it works.** A single conditional `UPDATE … SET stock = stock − q WHERE product_id = p AND stock >= q` checks and takes the stock in one step:
1. The first buyer locks the row.
2. The second waits for that lock.
3. When the first commits, PostgreSQL re-checks the second buyer's condition against the **new** stock. It is now false, so nothing is updated, and that buyer gets "Out of stock."

There is no gap between reading and writing, so there is nothing to race. No serialization error can occur, so there is nothing to retry and nothing reaches the caller as an error. The decrement, the order, the order line and the sale movement (with its `order_id`) commit together or not at all. `CHECK (stock_quantity >= 0)` is the safety net underneath.

**For flash-sale day:**
- Buyers of one product queue first come, first served on a per-product advisory lock. It wakes only the next in line, and measured 33% faster per call than queueing on the row lock alone.
- Once stock is gone, later buyers are refused from a plain read without queueing.
- `lock_timeout = 5s` turns an unusually long wait into "Too many buyers right now, please try again." rather than a spinner. The slowest measured wait was about 2.5 s, half the limit.

**Result:** the race test passed all four tests in every one of 11 consecutive runs. The 400-buyer, 50-unit sale completes in 3.7–4.0 s with exactly 50 sold.

| Rejected | Why |
|---|---|
| **Triggers alone** (what Nana was told) | Two orders arriving together each start their own transaction, each fires its own copy of the trigger, and neither can see the other's unfinished work, so both still believe the unit is available. A trigger plus the stock ≥ 0 rule would stop the stock going negative, but the losing buyer would get a crash instead of a clear "out of stock", possibly after their order was already written. Triggers are the right tool for the **audit trail** (goal 4), and that is where one is used. |
| `SERIALIZABLE` + retry | Correct, but on a flash sale most of the 400 transactions abort and retry, multiplying the work exactly when the server is busiest. The retry loop also becomes code to maintain. |
| `SELECT … FOR UPDATE`, then `UPDATE` | Correct too, but two statements and a decision in between, where one does the job. |
| `SKIP LOCKED` / `NOWAIT` | Skipping a locked product means acting as if it doesn't exist (wrong for stock). NOWAIT refuses buyers who would have got a unit a few milliseconds later. |
| A procedure with its own `COMMIT` | race_test calls `place_order` inside a `SELECT`, so it has to be a function. A function runs in one transaction, which is exactly the all-or-nothing behaviour wanted. |

**Promise, with its limit:** two buyers for the last unit, exactly one succeeds, verified by the supplied test over 11 full runs and a 400-way flash sale. This holds for every writer that changes stock through `place_order` or `record_movement`. A manual `UPDATE` can't oversell either, because the stock ≥ 0 rule refuses it, and the stock guard records it in the trail.

**Deducting at placement** (not at fulfilment, as the old process did) is what makes pending orders hold their stock. *Consequence:* a cancelled order must return its stock through `record_movement(…, 'return', …)`, or stock will drift low. This is not yet automated: recommended next.

## Goal 2: A fast Monday report

| Decision | Choice | Cost if wrong |
|---|---|---|
| What counts as spend | Completed + shipped orders. Not cancelled, refunded, or pending (pending may still cancel) | If Nana counts pending as spend, totals are about 10% low. One line in `v_report_orders` changes it, and every figure follows |
| Which amount | `orders.total_amount`, the figure of record from checkout | — (line items are the less reliable side, ADR/0004) |
| Future-dated orders | Excluded until their dates are confirmed | 24 orders, small |
| Trailing 12 months | 12 calendar months ending with the report date's month, oldest first; report date is a parameter (default today) | — |
| Running total | Per customer by order date, ties broken by `order_id` (`ROWS`, not `RANGE`), so two orders at the same moment show two steps | With `RANGE`, tied orders would both show the combined figure |
| Ranking | `RANK()`: tied customers share a place, so the list can be slightly over 100 rather than drop someone with equal spend | Today the top 100 is exactly 100 rows (no ties at the cut-off) |

**How it was made fast:** one pass over the orders instead of a lookup per figure per customer. The full report for 39,885 customers takes **1.3 s**, against an estimated **2 h 26 min** for the naive shape on the same laptop. Indexes then took one customer's running total from 32 ms to 0.23 ms.

**A bigger server would not have fixed it.** The naive report re-reads every order about 560,000 times. Twice the hardware leaves it at an hour or more.

**Materialized view rejected:** it would be fast but stale, and a plain refresh blocks readers, while the live query already meets the budget.

## Goal 3: Low-stock visibility, rolled up

- `low_stock_rollup(threshold)` walks the tree from the roots to whatever depth it has; no level is hard-coded.
- `CYCLE` stops the walk at a loop instead of running forever.
- Each product is counted once per ancestor, through its ancestor list, so nothing is double-counted. **Proof:** the top-level rows sum to 1,685, exactly the number of low-stock products.
- A category's figures **include** everything beneath it.
- Whole tree: **8 ms**.

**Assumed:** "low stock" means 5 units or fewer (a parameter); out of stock means 0. *If wrong:* change the default; nothing else moves.

## Goal 4: Proof of what happened

- **`place_order`** writes every sale movement with its `order_id`; the schema refuses a new sale without one.
- **`record_movement()`** is the one way to restock, return, damage, correct or count stock. It changes stock and writes the movement in one transaction. Sales are refused there, so every sale carries its order.
- **Stock guard trigger:** any other change to stock, such as a manual `UPDATE` in a terminal, is written to the log automatically as a correction, with the database user who made it. Nothing changes stock silently.
- **`v_stock_trail`:** every movement, the balance after it, the order and customer behind a sale, and who wrote it. One product's trail takes 0.5 ms.

**Verified (rolled back):** a restock followed by a manual decrement left two movements, and the trail balance equalled stock exactly.

**Limit:** history before this work has no order link, so the 144 stock mismatches flagged in cleaning still need a physical count.

## Assumptions the brief left open

| Assumption | Why | If wrong |
|---|---|---|
| Stock leaves at placement, order starts as `pending` | The only way a flash sale can't sell the same units twice | Cancellations must return stock (recommended next) |
| Spend = completed + shipped | Pending may still cancel; consistent with when stock left in the old process | One line changes it |
| Low stock = 5 units or fewer | Matches the stock distribution's low bands (0, 1, 2, 3, 5) | Parameter |
| `timestamp` stays local Accra time | GMT all year, no daylight saving | Revisit if Kloud Kart sells across time zones |
| Report date defaults to today | It is a Monday report; any date can be passed | — |
