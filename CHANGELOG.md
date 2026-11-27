# Changelog

All dates are 2026. Versions follow semantic versioning.

## 1.0.0 (2026-11-27)

First complete build against the lab bundle. Verified on a fresh load: 40-second build, race test passed 11 of 11 runs.

### Added
- `profiling/`: read-only data diagnosis, one file per table ([ADR/0001](ADR/0001-profile-data-with-read-only-sql.md), [ADR/0002](ADR/0002-data-diagnosis.md))
- `relationDATA/`: ERD foreign keys and six KPI reconciliations ([ADR/0003](ADR/0003-relationships-and-reconciliation.md))
- `cleaning/`: cleaning in ERD load order, with quarantine, change log and review list ([ADR/0004](ADR/0004-data-cleaning.md))
- `schema/upgrade.sql`: strict, scalable schema after cleaning ([ADR/0005](ADR/0005-schema-upgrade.md))
- `solution/`: `place_order`, low-stock rollup, Monday report, audit trail, indexes ([ADR/0006](ADR/0006-nanas-four-goals.md))
- `performance/`: before/after timings with full plans
- `solution/06_cancel_order.sql`: cancel a pending order and return its stock (improvement beyond the brief)
- `MEMO_TO_NANA.md`: one-page memo

### Environment
| Component | Version |
|---|---|
| PostgreSQL | 18.7 (`postgres:18.7` image), `max_connections = 500` |
| Docker Compose | v5.6.1 |
| Python | 3.15.2, `psycopg2-binary` 2.9.13 (race test only) |

### Changed during the build (evidence-driven)
- Duplicate order lines are removed only when the order total proves a double entry (38 genuine repeat purchases kept).
- Future-dated records are flagged, not quarantined (they are real movements with a wrong date).
- Cleaning reordered to follow the ERD hierarchy.
- `place_order`: first-come-first-served queue and fast refusal (33% less time per call under a 400-buyer flash sale).
