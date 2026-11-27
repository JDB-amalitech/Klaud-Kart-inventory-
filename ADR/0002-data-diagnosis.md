# 0002: Data diagnosis

- **Status:** Accepted
- **Date:** 2026-11-27
- **Method:** [0001](0001-profile-data-with-read-only-sql.md). Check IDs (P1, O3…) refer to the queries in `profiling/`. Run them all with `diagnosis.sql`.

## Context

Nana needs four things: no overselling, a fast and correct Monday report, a low-stock view rolled up through the category tree, and an audit trail of every stock movement. Nobody has audited the data, and the brief warns that some of what looks wrong isn't wrong.

This record ranks each problem by how much it threatens those four goals. For each one it says how it was found, how big it is, and what it costs Nana if left alone. Problems that look wrong but aren't are listed separately, so no effort is spent "fixing" them.

**Extract:**

| Table | Rows |
|---|---|
| categories | 94 |
| products | 4,023 |
| customers | 40,420 |
| orders | 159,384 |
| order_items | 336,559 |
| inventory_log | 282,352 |

Orders run from 2025-08-02 to 2026-08-31.

**Root cause:** the database has only primary keys (overview). It has no foreign keys, no check constraints and no unique constraints, so nothing has ever stopped the problems below from being written.

## Decision

The findings below are the agreed baseline. Records are not changed until a later ADR records the fix for each finding. Items under "Looks wrong, isn't" are left as they are, on purpose.

## Findings, ranked by danger

### 1. Stock on hand can't be trusted (goal: no overselling)

| Evidence | Check |
|---|---|
| 14 products have negative stock (as low as −4) | P2 |
| The negative-stock products are spread across the catalogue (sales rank 523 to 3,824 of 4,023), not concentrated on one hot product. The race is a general problem, not a one-off. | P3 |
| 144 products' `stock_quantity` doesn't match the inventory log's net movement (122 lower than the log, 22 higher, up to 56 units apart) | L3 |
| Stock only leaves the log when an order is **fulfilled**: 262,106 fulfilled order lines against 262,088 sale entries. Pending orders reserve nothing; 63,413 units are on pending orders right now. | L4 |

**Cost to Nana:** every oversell means a refund, an apology and a bad review. Because pending orders don't hold stock, a 400-orders-in-10-seconds flash sale can take every order before a single unit is deducted.

**Implication:** `place_order` must deduct stock when the order is placed, in the same transaction. Stock and the log need reconciling once, and from then on the log becomes the record stock is checked against.

### 2. The category tree contains a loop and a broken branch (goal: low-stock rollup)

| Evidence | Check |
|---|---|
| Categories `9001` and `9002` are each other's parent. They hold 6 products. | P1 |
| Category `9003 Clearance` points to parent `8999`, which doesn't exist | P1 |
| 37 products have no category | P2 |
| The rest of the tree is healthy: 7 roots, depth 1 to 4, and products only at depth 3 and 4 | P1 |

**Cost to Nana:** a simple recursive rollup either never finishes (it follows the loop forever) or silently leaves these products out. The low-stock screen hangs, or shows "fine" for stock it never counted. P1 itself uses PostgreSQL's `CYCLE` clause, which is how the real rollup must guard against loops.

### 3. Order totals disagree with their line items (goal: correct report)

2,426 orders: `total_amount` ≠ sum of `quantity × unit_price`. Check O3 groups them by cause:

| Cause | Orders | Effect on line totals | Check |
|---|---|---|---|
| A line inserted twice (578 exact duplicate lines). In 104 orders the stored total is exactly half the line total. | 536 | Line items overstate by 900,082 | O3, I1 |
| Quantity of 999 or 9999 (normal maximum is 10) | 6 | Line items overstate by 3,059,983 | O3, I2 |
| Null or zero `unit_price` (148 / 152 lines) | 294 | Line items understate by 522,696 | O3, I1 |
| No visible cause | 1,590 | Net difference 36,675 | O3 |

**Cost to Nana:** Adwoa's revenue figures move by millions depending on which column she sums. For the explained causes, `total_amount` (written at checkout) is the more reliable figure. Summing line items would count duplicates and the 9999-quantity lines.

### 4. Order status is free text (goal: correct report)

15 spellings for 5 states. They differ in case, one has a leading space (`" completed"`), and two words have two spellings (`canceled`/`cancelled`, `complete`/`completed`). Check O1.

**Cost to Nana:** a report that filters on `status = 'completed'` finds **22,091 of 111,351** completed orders, about 20%. It would under-report revenue by about 80% with no error message. Every report and the oversell logic depend on reading status correctly.

### 5. One customer, several accounts (goal: correct report)

| Evidence | Check |
|---|---|
| 535 surplus accounts share an email with another account once case and spaces are ignored. 1,314 emails have stray spaces, which is the **only** reason any email fails validation (0 invalid after trimming). | C1 |
| 513 people have orders on more than one account, with 12.6M of spending split between accounts | C2 |
| Merging accounts changes 3 of the top-100 spenders | C2 |

**Cost to Nana:** per-customer totals, order counts and the running total Adwoa tracks are wrong for 513 customers, and 3 deserving customers are missing from the top 100.

### 6. Records that point to rows that don't exist (goals: report, audit)

| Evidence | Check |
|---|---|
| 210 orders belong to customer IDs that don't exist, all in the range 999007 to 999997 (test or placeholder IDs) | O2 |
| 692 order lines belong to orders that don't exist | I1 |
| 120 log entries are for products that don't exist (IDs in the 99xxx range) | L2 |

**Cost to Nana:** any report that joins tables drops these rows without warning, so revenue and stock movements disappear from the totals. The auditor finds movements for products that don't exist.

### 7. The audit trail can't prove what happened (goal: audit trail)

| Evidence | Check |
|---|---|
| Sale entries carry no `order_id`, so a movement can't be traced to the order that caused it | L4 (schema) |
| 18 fulfilled order lines have no sale entry | L4 |
| 425 notes are informal: `??`, `see WhatsApp msg`, `recount, not applied`, `POS mismatch` | L2 |
| Nothing records who made a change or why, beyond the free-text note | schema |

**Cost to Nana:** an auditor can't walk from a refund back to the stock movement and the order. "Recount, not applied" is itself evidence that stock and the log were allowed to drift apart.

### 8. Dates after the end of the extract (goal: report)

24 orders are dated after the extract ends (2026-08-31), up to 2027-08-20; 15 of them are later than today. 33 log entries are dated in the future. Checks O2 and L2.

**Cost to Nana:** "last 12 months" and "this month" figures pick up orders that haven't happened, and future months show revenue in the trailing-12-month report.

### 9. Cosmetic: fix when convenient

| Evidence | Check |
|---|---|
| 4,994 names not in Title Case (ALL UPPER, all lower, stray spaces) | C1 |
| Phone numbers in 5 formats (`+233…`, `233…`, `0…`, no prefix, spaced) | C1 |
| `Accra` spelled 4 ways (15 raw city values → 12 cities) | C1 |

**Cost to Nana:** small. These matter for display and for grouping by city, not for money or stock. City needs normalising only if a report groups by city.

## Looks wrong, isn't: leave alone

| Observation | Why it's correct | Check |
|---|---|---|
| 3,964 order lines priced below the product's current price | `unit_price` is the price **at the time of sale**, and prices change. Rewriting it would falsify past revenue. None are above the current price. | I1 |
| 577 products with zero stock | Sold out is a normal state | P2 |
| 435 repeated product names | Different products with different IDs, prices and categories; names are brand + type + variant | P2 |
| Prices from 5.04 to 21,961.78 | The catalogue mixes groceries and electronics | overview |
| `canceled` vs `cancelled`, `complete` vs `completed` | Same meaning. Map them; don't delete them. | O1 |
| `timestamp` without time zone | Accra is on GMT all year with no daylight saving, so local time is unambiguous while the business runs in Ghana | schema |
| Pending, cancelled and refunded orders have no sale movement | Matches the current process (stock leaves at fulfilment). The problem is the process (finding 1), not the data. | L4 |
| `correction` entries in both directions; 90 `stock_take` entries of 0 | Corrections go both ways, and a stock take that confirms the count records no change | L1 |
| Customers in Lagos and Abuja | Plausible Nigerian customers, not a data error | C1 |
| No order before its customer registered; no log entry before its product existed | Checked, and clean | O2, L2 |

## Consequences

- **Overselling (finding 1):** fixed by the order-placement function, which deducts stock at placement under a row lock. It is decided in a later ADR, along with why triggers alone are not enough.
- **Report (findings 3 to 5, 8):** must read normalised status, use `total_amount`, merge accounts by normalised email, and exclude orders after the extract end. These rules are decided in the reporting ADR.
- **Rollup (finding 2):** must use cycle-safe recursion and must not hard-code the tree depth. The loop and the orphan category need a decision on where they belong.
- **After cleaning:** add foreign keys, a unique index on `lower(btrim(email))`, a check on status values, `CHECK (stock_quantity >= 0)`, `CHECK (quantity > 0)`, and `order_id` on `inventory_log`, so these problems can't be written again.
