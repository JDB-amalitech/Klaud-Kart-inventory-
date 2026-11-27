# Post-cleaning validation

- **Taken:** 2026-11-27, after `relationDATA/relationship.sql` and `cleaning/clean_all.sql` on a fresh load. Cleaning runs in the ERD hierarchy order: Level 0 categories and customers, Level 1 products and orders, Level 2 inventory_log and order_items
- **Raw output:** `cleaning_run.txt`, `post_cleaning_diagnosis.txt`, `post_cleaning_reconciliation.txt`
- **Compared against:** [PRE_VALIDATION.md](PRE_VALIDATION.md)

## Before / after

| # | KPI | Before | After | Target | |
|---|---|---|---|---|---|
| R1 | orders → customers match | 99.87% (210 orphans) | **100%** | 100% | ✅ |
| R1 | order_items → orders match | 99.79% (692 orphans) | **100%** | 100% | ✅ |
| R1 | inventory_log → products match | 99.96% (120 orphans) | **100%** | 100% | ✅ |
| R1 | categories → parent match | 98.85% | **100%** | 100% | ✅ |
| R2 | orders reconciled to their lines | 98.48% | **98.81%** | 100% | ▲ |
| R2 | absolute variance (GHS) | 5,291,592 | **1,361,086** (−74%) | 0 | ▲ |
| R2 | net variance (GHS) | −3,400,694 | **+553,233** | 0 | ▲ |
| R3 | stock accuracy | 96.42% | 96.42% | 100% | ⏸ needs physical count |
| R3 | products oversold (< 0) | 14 | **0** | 0 | ✅ |
| R3 | units on pending orders, not deducted | 63,413 | 53,228 | 0 | ⏸ fixed by `place_order` |
| R4 | sale movement coverage | 99.993% | 100.244% | 100% | ⚠ see below |
| R5 | duplicate account rate | 1.32% (535) | **0%** | 0% | ✅ |
| R6 | products covered by rollup | 98.93% (43 invisible) | **100%** | 100% | ✅ |
| O1 | status values | 15 spellings | **5** | 5 | ✅ |
| — | foreign keys validated | 0 of 6 | **6 of 6** | 6 of 6 | ✅ |
| — | check rules | 0 | **3** (status, quantity > 0, stock ≥ 0) | — | ✅ |

## What moved, and why

- **R2:** removing the proven double-entry lines and the 999/9999 quantities closed 74% of the money gap. The remaining 1.36M sits in 296 orders with unpriced lines and 1,599 with no visible cause, all listed in `cleaning.review`. Totals were not overwritten.
- **R3:** stock accuracy is unchanged **by design**. Neither stock nor the log is guessed; the 144 products are listed for a physical count. Pending units fell only because quarantined orders took their lines with them. The real fix is deducting stock at order placement (`place_order`).
- **R4 above 100% is a finding, not an error.** The 776 fulfilled lines that were quarantined still have their stock movements in the log (355 lines from "unknown customer" orders, 418 duplicate copies, 3 extreme lines). So:
  - the orders with an unknown customer were **real sales**: stock left the shelf; only the customer ID is broken
  - for the duplicate copies, either the customer took both units and was under-charged, or the double entry happened in the stock log too
  
  The log has no `order_id`, so I can't tell which. Both are reversible: the rows sit in `quarantine.*`.

## Where everything went

| Kept in | Rows |
|---|---|
| `quarantine.order_items` | 1,695 (692 order missing, 471 unknown customer, 6 extreme quantity, 526 double entries) |
| `quarantine.orders` | 212 (210 unknown customer, 2 left with no lines) |
| `quarantine.customers` | 535 merged duplicates |
| `quarantine.inventory_log` | 120 movements for products that don't exist |
| `cleaning.change_log` | every changed value, old and new |
| `cleaning.review` | 2,402 rows for a person: 299 unpriced lines, 1,895 order totals, 64 future-dated rows, 144 stock counts |

## Race test at cleaning time

Not run then: `place_order` didn't exist yet. See the next section for the result after the solution.

## After the solution (`solution/solution_all.sql`, PostgreSQL 18, max_connections 500)

| Check | Before | After |
|---|---|---|
| Race test preflight | FAIL: no `place_order` | passes |
| 1. Two buyers, one unit (×25) | not reached | **PASS** (25/25) |
| 2. Flash sale, 400 buyers, 50 units | not reached | **PASS**: exactly 50 sold, 0 errors, 3.7–4.0 s |
| 3. Oversell attempt | not reached | **PASS** |
| 4. Trail intact | not reached | **PASS** |
| Consecutive full passes | — | 11 of 11 |

Raw output: `post_solution_race_test.txt`, `post_solution_reconciliation.txt`. Timings: `performance/README.md`.
