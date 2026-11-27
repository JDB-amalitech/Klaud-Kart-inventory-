# 0004: Data cleaning

- **Status:** Accepted
- **Date:** 2026-11-27
- **Files:** `cleaning/00_setup.sql`, then one file per table in the ERD's load order (`01_categories` to `06_order_items`), run by `cleaning/clean_all.sql`
- **Evidence:** `validation/PRE_VALIDATION.md` → `validation/POST_VALIDATION.md`

## Context

[0002](0002-data-diagnosis.md) ranked the problems; [0003](0003-relationships-and-reconciliation.md) set the KPIs. Nana's team has to trust and maintain what is left, and nobody is available to confirm individual records.

## Decisions

| Principle | Why |
|---|---|
| **Quarantine, never delete** (`quarantine.*` keeps the row, the reason and the step) | Every removal can be inspected and reversed. Two of them turned out to be real business data. |
| **Log every change** (`cleaning.change_log`, old and new values) | An auditor can trace any cleaned value back to what was loaded. |
| **Flag what the data can't settle** (`cleaning.review`) | Guessing a price, a total or a stock figure would make the data look clean while being wrong. |
| **Add the rule once a step makes it true** (FK `VALIDATE`, `CHECK`, unique index) | The database then stops the problem from coming back. |
| **Re-runnable steps, bounded to the original extract** (`cleaning.extract`) | Running a step twice changes nothing, and can never touch real new orders after go-live. |

### Order: the ERD hierarchy

The steps follow the load order in `Diagrams/sales_erd_hierarchy.drawio`. Each parent is cleaned and its rule enforced before any child that points at it, so a child is never cleaned against a parent that is still about to change. For example, orders are checked against customers only after the customers are merged.

| Level | File | Table (diagram order) | Rule enforced at the end |
|---|---|---|---|
| — | 00_setup | quarantine, change log, review list, extract bounds | — |
| 0 | 01_categories | categories + sub-categories (1, 3) | `fk_categories_parent` validated |
| 0 | 02_customers | customers (2) | unique email |
| 1 | 03_products | products (4) | `fk_products_category` validated; `stock >= 0` |
| 1 | 04_orders | orders (5) | status `CHECK`; `fk_orders_customer` validated |
| 2 | 05_inventory_log | inventory (6) | `fk_inventory_log_product` validated |
| 2 | 06_order_items | order_items (7) | both FKs validated; `quantity > 0` |

Two steps have to reach across a level because a foreign key requires it:
- 04 quarantines the lines of an order it removes, since the key refuses to orphan a line.
- 06 quarantines an order left with no lines.

### Decisions per table

| File | Decision | Rejected alternative |
|---|---|---|
| 01 categories | 9002 Promotions made top-level (breaks the loop, keeps Seasonal Promotions under it); 9003 Clearance made top-level; new 9900 Uncategorised | Guess deeper parents: puts stock in the wrong branch of the screen |
| 02 customers | Trim and lower-case emails, trim names, Title Case cities (name casing left alone). Then merge same email **and** same name into the earliest account | Rewriting name casing: cosmetic, and risks names like "McDonald". Merging on email alone: could join two people who share an inbox |
| 03 products | 37 uncategorised → 9900. Negative stock → 0 with a `correction` movement in the log. 144 mismatches listed for a physical count | Overwrite stock from the log, or the log from stock: no evidence which side is right |
| 04 orders | Status mapped to 5 values. Unknown-customer orders quarantined with their lines. Future-dated orders **flagged only** | Normalise status in every report: every future query has to remember. Delete unknown-customer orders: they are real sales (see consequences) |
| 05 inventory_log | Movements for missing products quarantined. Future-dated movements **flagged only** | Quarantine future movements: for 39 products stock only matches the log with them kept, so they are real movements with a wrong date |
| 06 order_items | Missing-order lines and 999/9999 lines quarantined. A duplicate is quarantined **only when the order total proves it was entered twice**. Unpriced lines and remaining total gaps flagged; `total_amount` never overwritten | Removing every identical copy: 38 orders had totals that already counted both lines (genuine repeat purchases). Overwrite totals from lines: the lines are the less reliable side |

## Consequences

- R1, R5 and R6 reached their targets. All 6 foreign keys are validated, with 3 check rules and a unique email index ([POST_VALIDATION.md](../validation/POST_VALIDATION.md)).
- **What the cleaning revealed:** the 210 "unknown customer" orders have stock movements, so they are real sales with a broken customer ID, not test data. Their 355 fulfilled lines sit in quarantine and can be restored once the customers are identified.
- **Can't stand behind:**
  - Whether the 418 fulfilled duplicate copies were under-charged repeat purchases or a double entry in both the lines and the stock log. It can't be decided without `order_id` on the log.
  - The 1,599 order totals with no visible cause.
  - The 144 stock mismatches, until they are counted.
- **Recommended:** add `order_id` to `inventory_log` (`place_order` will write it), so this ambiguity can't arise for new sales.
- **Undo:** reload from the CSVs, or move rows back from `quarantine.*`.
