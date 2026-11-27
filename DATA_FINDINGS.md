# Kloud Kart: Data Findings

- **Date:** 2026-11-27
- **Scope:** the full extract, loaded fresh with `docker compose up`, then profiled and reconciled read-only. Nothing has been cleaned.
- **Evidence:** every figure below comes from a query that can be re-run:
  - check IDs (P1, C2, O3, I1, L4) are in `profiling/`, run with `diagnosis.sql`
  - reconciliation IDs (R1 to R6) are in `relationDATA/reconciliation.sql`
- **Full reasoning:** [ADR/0002](ADR/0002-data-diagnosis.md) (diagnosis), [ADR/0003](ADR/0003-relationships-and-reconciliation.md) (relationships and KPIs)

| Table | Rows | | Table | Rows |
|---|---|---|---|---|
| categories | 94 | | orders | 159,384 |
| products | 4,023 | | order_items | 336,559 |
| customers | 40,420 | | inventory_log | 282,352 |

Orders run from 2025-08-02 to 2026-08-31.

---

## Summary

The database enforces nothing beyond primary keys: no foreign keys, no checks, no unique rules. Every problem below got in through that gap. Findings are ranked by what they cost Nana's four goals (no overselling, a correct and fast Monday report, a low-stock rollup, an audit trail), not by how many rows are affected.

| Rank | Finding | Goal threatened | Headline figure |
|---|---|---|---|
| 1 | Stock can't be trusted, and pending orders reserve nothing | No overselling | 14 products oversold; 63,413 units unreserved; 96.42% stock accuracy |
| 2 | Order totals disagree with their lines | Report | 2,426 orders; 5.29M GHS absolute variance |
| 3 | Order status is free text | Report | A `'completed'` filter finds 20% of completed orders |
| 4 | Category tree has a loop and a broken branch | Low-stock rollup | 43 products invisible; a naive rollup never ends |
| 5 | Records point to rows that don't exist | Report, audit | 1.49M GHS dropped by joins |
| 6 | One person, several accounts | Report | 513 people's spend split; 12.6M GHS |
| 7 | Audit trail can't link a movement to its order | Audit trail | 0% of sale movements traceable to an order |
| 8 | Orders and movements dated after the extract | Report | 24 orders, 33 movements |
| 9 | Cosmetic inconsistencies | Display only | Names, phones, city spellings |

**Fixed already:** the six ERD relationships are now enforced for **new** writes (`relationDATA/relationship.sql`, `NOT VALID`). From now on no new orphan can be written. Existing orphans are kept for a cleaning decision.

---

## Findings

Each finding has four parts: **what is wrong** (named by the rule that would have prevented it), **how it was found**, **what it costs**, and **what to do** (including the fix's own risk).

### 1. Stock on hand can't be trusted

| | |
|---|---|
| **What is wrong** | No `CHECK (stock_quantity >= 0)`. **14 products** are below zero (as low as −4). **144 products'** stock doesn't match the inventory log's net movement (2,553 units in total, worst gap 56). Stock leaves the log only when an order is **fulfilled**, so **63,413 units** on 16,009 pending orders are reserved nowhere. |
| **How found** | P2, P3 (negative stock and its sales rank); L3 and R3 (stock against log); L4 (262,106 fulfilled lines against 262,088 sale entries, so sales are logged at fulfilment). |
| **What it costs** | Every oversell costs a refund, an apology and a review. The 14 oversold products are spread across the catalogue (sales rank 523 to 3,824 of 4,023), so this is a general flaw, not one hot product. In a 400-orders-in-10-seconds flash sale nothing is deducted until fulfilment, so every buyer can be "sold" the same units. Only 96.42% of the catalogue has a stock figure the trail can prove. |
| **What to do** | Deduct stock **at order placement**, inside the same transaction, under a row lock (`place_order`). Add `CHECK (stock_quantity >= 0)` as a safety net. Reconcile the 144 products once, then treat the log as the record. **Risk:** moving deduction to placement means cancellations must return stock, or it will drift the other way. |

### 2. Order totals disagree with their lines

| | |
|---|---|
| **What is wrong** | Nothing ties `orders.total_amount` to its line items. **2,426 orders (1.52%)** disagree by more than 0.01. |
| **How found** | O3 groups the gap by cause; R2 measures it. |
| **Causes** | 536 orders have a line inserted twice (578 exact duplicate lines; in 104 of them the stored total is exactly half the line total). 6 lines have a quantity of 999 or 9999 (the normal maximum is 10), worth 3.06M on their own. 294 orders have lines with a null or zero price (148 null, 152 zero). 1,590 have no visible cause. |
| **What it costs** | Adwoa's "total spent" moves by **5,291,592 GHS** depending on which column she sums. Summing line items overstates revenue by a net **3,400,694 GHS**, because of the duplicates and the 9999s. |
| **What to do** | The report uses `total_amount` (written at checkout, and right in the explained cases). Quarantine the 6 extreme lines and remove exact duplicate lines after review. **Risk:** two identical lines could be a real repeat purchase. Review before deleting. |

### 3. Order status is free text

| | |
|---|---|
| **What is wrong** | No `CHECK` on status. **15 spellings for 5 states**: differences in case, a leading space (`" completed"`, 22,395 rows), and two words with two spellings (`canceled`/`cancelled`, `complete`/`completed`). |
| **How found** | O1. |
| **What it costs** | A report filtering on `status = 'completed'` finds **22,091 of 111,351** completed orders (about 20%). Revenue is under-reported by roughly 80%, with no error message. |
| **What to do** | Map to five official values (`pending`, `shipped`, `completed`, `cancelled`, `refunded`), then add a `CHECK`. **Risk:** none to the data; any application writing other spellings will be refused and must be updated. |

### 4. The category tree has a loop and a broken branch

| | |
|---|---|
| **What is wrong** | The parent reference has no FK. Categories **9001 and 9002** are each other's parent (6 products sit in them). **9003 Clearance** points to parent **8999**, which doesn't exist. **37 products** have no category. The rest is healthy: 7 roots, depth 1 to 4. |
| **How found** | P1 (a recursive walk with PostgreSQL's `CYCLE` clause); R6. |
| **What it costs** | A naive recursive low-stock rollup never finishes: it follows the loop forever, with no error. A guarded one silently leaves out **43 products (1.07%)**, so the screen says "fine" about stock it never looked at. |
| **What to do** | The rollup uses cycle-safe recursion and no fixed depth. Re-parent 9001, 9002 and 9003, and categorise the 37. **Risk:** guessing the wrong parent moves stock into the wrong branch of the screen. |

### 5. Records that point to rows that don't exist

| | |
|---|---|
| **What is wrong** | No foreign keys. **210 orders** belong to customer IDs that don't exist, all in the range 999007 to 999997 (test or placeholder values). **692 order lines** belong to orders that don't exist. **120 log entries** are for products that don't exist (99xxx IDs). |
| **How found** | O2, I1, L2; R1 (match rate and value at risk). |
| **What it costs** | Any report that joins tables drops these rows without warning: **665,181 GHS** of orders and **826,328 GHS** of line value. The auditor also finds stock movements for products that don't exist. |
| **What to do** | New orphans are already blocked (`NOT VALID` FKs). Move existing orphans to a quarantine table, then `VALIDATE` each constraint. **Risk:** deleting them outright loses evidence of whatever process created them. |

### 6. One person, several accounts

| | |
|---|---|
| **What is wrong** | No unique rule on email. Ignoring case and spaces, **535 surplus accounts** share an email (1.32% of customers). **1,314 emails** have stray spaces, which is the only reason any email fails validation (0 are invalid after trimming). |
| **How found** | C1, C2; R5. |
| **What it costs** | **513 people** have orders on more than one account, with **12.6M GHS** of spend split between them. Their per-customer totals, order counts and running totals are wrong, and **3** of the true top-100 spenders are missing from the ranking. |
| **What to do** | Merge on normalised email after review, then add a unique index on `lower(btrim(email))`. **Risk:** two real people sharing an inbox would be merged, so review before merging. |

### 7. The audit trail can't prove what happened

| | |
|---|---|
| **What is wrong** | `inventory_log` has no `order_id`, so no sale movement can be traced to its order. **18 fulfilled lines** have no movement at all. **425 notes** are informal (`??`, `see WhatsApp msg`, `recount, not applied`, `POS mismatch`). Nothing records who made a change. |
| **How found** | L2, L4; R4 (99.993% coverage). |
| **What it costs** | An auditor can't walk from a refund to its stock movement. "Recount, not applied" is itself evidence that stock and the log were allowed to drift apart. |
| **What to do** | Add `order_id` to the log, and have `place_order` write the movement in the same transaction as the order. **Risk:** one extra column and write per sale. Negligible. |

### 8. Dates after the end of the extract

| | |
|---|---|
| **What is wrong** | **24 orders** are dated after the extract ends (2026-08-31), up to 2027-08-20; 15 of them are later than today. **33 log entries** are dated in the future. |
| **How found** | O2 (the extract end is the last day with 100+ orders); L2. |
| **What it costs** | "Trailing 12 months" and "this month" figures include orders that haven't happened. |
| **What to do** | The report excludes dates after the extract end until the cause is known (wrong year, or test data). **Risk:** small. These are 24 of 159,384 orders. |

### 9. Cosmetic: fix when convenient

| Finding | Count | Check |
|---|---|---|
| Names not in Title Case (ALL UPPER, lower case, stray spaces) | 4,994 | C1 |
| Phone numbers in 5 formats (`+233…`, `233…`, `0…`, no prefix, spaced) | about 8k each | C1 |
| `Accra` spelled 4 ways (15 raw city values → 12 cities) | 15 → 12 | C1 |

These affect display and grouping by city, not money or stock.

---

## Looks wrong, but isn't: left alone on purpose

| Observation | Why it's correct |
|---|---|
| 3,964 order lines priced below today's product price | `unit_price` is the price **at the time of sale**, and prices change. None are above today's price. Rewriting them would falsify past revenue. |
| 577 products with zero stock | Sold out is a normal state. |
| 435 repeated product names | Different products, with different IDs, prices and categories. |
| Prices from 5.04 to 21,961.78 | The catalogue mixes groceries and electronics. |
| `timestamp` without time zone | Accra is on GMT all year with no daylight saving, so local time is unambiguous while the business runs in Ghana. |
| Pending, cancelled and refunded orders have no sale movement | Matches the current process. The flaw is the process (finding 1), not the data. |
| Negative `change_qty`, corrections in both directions, `stock_take` entries of 0 | That is how outward movements, adjustments and confirmed counts are recorded. |
| Customers in Lagos and Abuja | Plausible Nigerian customers. |
| No order before its customer registered; no movement before its product existed | Checked, and clean. |

---

## What I can't yet stand behind

- **The cause of 1,590 order-total gaps.** None of the visible causes explain them. They are worth a net 36,675 GHS, which is small, but unexplained.
- **Which side is right in the 144 stock-to-log mismatches.** The data alone can't settle it. It needs a physical count of those products.
- **Whether the 535 duplicate accounts are all the same person.** A shared email strongly suggests it but doesn't prove it.
- **Where the 999/9999 quantities and the 999xxx customer IDs came from.** They look like test data or input errors. Only the people who wrote them can confirm.

## How to reproduce

```bash
docker compose up -d --wait
docker exec kloudkart-db psql -U kloudkart -d kloudkart -f /profiling/diagnosis.sql
docker exec kloudkart-db psql -U kloudkart -d kloudkart -f /relationDATA/relationship.sql
docker exec kloudkart-db psql -U kloudkart -d kloudkart -f /relationDATA/reconciliation.sql
```
