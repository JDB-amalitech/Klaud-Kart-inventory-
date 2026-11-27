# 0001: Profile the data with read-only SQL before cleaning

- **Status:** Accepted
- **Date:** 2026-11-27

## Context

Kloud Kart's extract is loaded into PostgreSQL 17 by `docker compose up`. The brief says the data is messy on purpose, that not everything that looks wrong is wrong, and that the solution must run on the existing PostgreSQL server with no new tools. Cleaning before measuring risks fixing harmless things and missing dangerous ones.

## Decision

1. **Diagnose first.** Profiling only measures. Nothing is changed.
2. **Plain SQL on the live database.** The checks see exactly what `place_order` and the reports will see, with no extra tools to run.
3. **Read-only by construction.** `diagnosis.sql` sets `default_transaction_read_only = on` once, for the whole run.
4. **One entry point, one file per table, no repeated code:**

   | File | Role |
   |---|---|
   | `profiling/diagnosis.sql` | Entry point: session setup, a column profile of every column of every table (one generic query), and the constraint list. Then it runs each file below. |
   | `profiling/products.sql` | P1 to P3: category tree health (cycle-safe), stock, oversold products |
   | `profiling/customers.sql` | C1, C2: duplicates, formats, split spending |
   | `profiling/orders.sql` | O1 to O3: status, references, dates, totals against line items |
   | `profiling/order_items.sql` | I1, I2: references, duplicates, quantities, prices |
   | `profiling/inventory_log.sql` | L1 to L4: movement directions, references, stock reconciliation, when sales are logged |

5. **Short checks.** Each check is one query that returns a few headline numbers. It doesn't dump rows.
6. **Run:** `docker exec kloudkart-db psql -U kloudkart -d kloudkart -f /profiling/diagnosis.sql`. The `profiling/` folder is mounted read-only into the container.

## Consequences

- Findings, ranked by danger, are in [0002](0002-data-diagnosis.md). Each finding cites its check ID.
- `diagnosis.sql` uses psql commands (`\ir`, `\echo`). The table files are plain PostgreSQL and also run in a GUI client such as Database Client. When run that way, the read-only setting isn't applied, but the files contain only `SELECT` statements.
- The SQL is PostgreSQL-only (`CYCLE`, `FILTER`, `query_to_xml`). VS Code's SQL Server extension marks it with false syntax errors.
- After cleaning, re-running the checks proves each fix: the relevant counts should drop to zero.
