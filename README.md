# Klaud-Kart Inventory

Kloud Kart's PostgreSQL database: diagnosed, cleaned, made strict, and extended to meet Nana's four goals: no overselling, a fast Monday report, a low-stock rollup, and an audit trail.

| Folder / file | What it is |
|---|---|
| `M03_Resources/` | The lab bundle: `schema.sql` (as-is schema, left untouched as the baseline), `load.sql`, CSVs, `race_test.py` |
| `Diagrams/` | ERD and load hierarchy (draw.io) |
| `profiling/` | Read-only data diagnosis (`diagnosis.sql` runs the per-table files) |
| `relationDATA/` | ERD relationships as foreign keys (`relationship.sql`) and KPI reconciliations (`reconciliation.sql`) |
| `cleaning/` | One file per table in ERD load order (`clean_all.sql`). Bad rows go to `quarantine.*`, changes to `cleaning.change_log` |
| `schema/upgrade.sql` | Strict, scalable schema after cleaning: bigint and automatic ids, NOT NULL, defaults, value rules, order-linked audit trail |
| `solution/` | Nana's four goals: `place_order`, low-stock rollup, Monday report, audit trail, indexes (`solution_all.sql`) |
| `performance/` | Before/after timings with full query plans (`README.md`) |
| `validation/` | Before/after evidence for cleaning and the race test |
| `DATA_FINDINGS.md` | The written data diagnosis, ranked by danger |
| `ADR/` | Decision records: why each choice was made, and what was rejected |

## Setup

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

## Build and test (PostgreSQL 18 in Docker, about 40 seconds from a fresh load)

```powershell
docker compose up -d --wait   # fresh load: lab schema.sql + load.sql

docker exec kloudkart-db psql -U kloudkart -d kloudkart -f /relationDATA/relationship.sql
docker exec kloudkart-db psql -U kloudkart -d kloudkart -f /cleaning/clean_all.sql
docker exec kloudkart-db psql -U kloudkart -d kloudkart -f /schema/upgrade.sql
docker exec kloudkart-db psql -U kloudkart -d kloudkart -f /solution/solution_all.sql

$env:DATABASE_URL = "postgresql://kloudkart:kloudkart@localhost:5432/kloudkart"
python M03_Resources/race_test.py
```

## Using it

| Need | Run |
|---|---|
| Sell stock | `SELECT * FROM place_order(customer_id, product_id, quantity);` |
| Restock / return / damage / count | `SELECT record_movement(product_id, change, 'restock', 'note');` |
| Monday report (today, or any date) | `SELECT * FROM v_monday_report;` or `SELECT * FROM monday_report('2026-08-31');` |
| Top 100 customers | `SELECT * FROM v_top_100_customers;` |
| Running total per customer | `SELECT * FROM v_customer_running_total WHERE customer_id = …;` |
| Low stock, rolled up | `SELECT * FROM v_low_stock_rollup;` or `SELECT * FROM low_stock_rollup(10);` |
| Low-stock products | `SELECT * FROM v_low_stock_products;` |
| Audit trail for a product | `SELECT * FROM v_stock_trail WHERE product_id = … ORDER BY created_at, log_id;` |

- Connect: `docker exec -it kloudkart-db psql -U kloudkart -d kloudkart`
- Override credentials/port: copy `.env.example` to `.env` and edit.
- Diagnosis: `docker exec kloudkart-db psql -U kloudkart -d kloudkart -f /profiling/diagnosis.sql`
- Timings: `docker exec kloudkart-db psql -U kloudkart -d kloudkart -f /performance/measure.sql`
- Reload from scratch: `docker compose down -v; docker compose up -d --wait`
