# Architecture Decision Records

Decisions and findings for the Kloud Kart inventory work. Records are numbered and are not rewritten once accepted; a later record replaces an earlier one.

| # | Title | Status | Date |
|---|---|---|---|
| [0001](0001-profile-data-with-read-only-sql.md) | Profile the data with read-only SQL before cleaning | Accepted | 2026-11-27 |
| [0002](0002-data-diagnosis.md) | Data diagnosis: problems ranked by danger to Nana's four goals | Accepted | 2026-11-27 |
| [0003](0003-relationships-and-reconciliation.md) | Enforce the ERD relationships, and reconcile with business KPIs | Accepted | 2026-11-27 |
| [0004](0004-data-cleaning.md) | Data cleaning: quarantine, log, flag, then enforce | Accepted | 2026-11-27 |
| [0005](0005-schema-upgrade.md) | Schema upgrade for clean, scalable data | Accepted | 2026-11-27 |
| [0006](0006-nanas-four-goals.md) | How Nana's four goals are met (overselling, report, rollup, audit trail) | Accepted | 2026-11-27 |

Each record has three sections: **Context** (the situation), **Decision** (what was chosen), **Consequences** (what follows). Findings cite the check ID of the query in `profiling/` that produced them.
