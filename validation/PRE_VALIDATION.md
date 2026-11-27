# Pre-validation baseline

- **Taken:** 2026-11-27, before any cleaning or correction
- **Database:** fresh load of the extract, plus the six foreign keys from `relationDATA/relationship.sql` (`NOT VALID`: they check new writes only, no data changed)
- **Raw output:** `pre_diagnosis.txt`, `pre_reconciliation.txt`, `pre_race_test.txt` in this folder

After each correction, re-run the same three commands into `post_<step>_*.txt` and compare against the table below. Every KPI should move toward its target and none should get worse.

## KPI baseline

| # | KPI | Baseline | Target |
|---|---|---|---|
| R1 | orders → customers match rate | 99.87% (210 orphans, 665,180.61 GHS at risk) | 100% |
| R1 | order_items → orders match rate | 99.79% (692 orphans, 826,327.80 GHS at risk) | 100% |
| R1 | inventory_log → products match rate | 99.96% (120 orphans) | 100% |
| R1 | categories → parent match rate | 98.85% (1 orphan) | 100% |
| R1 | products → categories match rate | 100% (37 NULL) | 100% |
| R1 | order_items → products match rate | 100% | 100% |
| R2 | orders reconciled to their lines | 98.48% | 100% |
| R2 | absolute / net variance (GHS) | 5,291,591.64 / −3,400,693.90 | 0 / 0 |
| R3 | stock accuracy (stock = log net) | 96.42% | 100% |
| R3 | absolute unit variance | 2,553 | 0 |
| R3 | products already oversold (< 0) | 14 | 0 |
| R3 | units on pending orders, not deducted | 63,413 | 0 |
| R4 | sale movement coverage | 99.993% (18 lines with no movement) | 100% |
| R4 | unit variance (sold − logged) | 3,067 | 0 |
| R5 | duplicate account rate | 1.32% (535 surplus accounts) | 0% |
| R6 | products covered by the category rollup | 98.93% (43 invisible) | 100% |
| O1 | status spellings → states | 15 → 7 normalised (5 real states) | 5 → 5 |
| — | foreign keys validated | 0 of 6 | 6 of 6 |

## Race test baseline

| Test | Baseline | Target |
|---|---|---|
| Preflight | **FAIL**: no function named `place_order` | passes |
| 1. Two buyers, one unit (×25) | not reached | PASS every round |
| 2. Flash sale (400 buyers, 50 units) | not reached | PASS |
| 3. Oversell attempt | not reached | PASS |
| 4. Trail intact | not reached | PASS |

## Environment issues to fix before the race test can pass

| Setting | Now | Required | Why |
|---|---|---|---|
| `max_connections` | 100 | 500 | Test 2 opens 400 connections at once; on 100, most buyers can't connect and the test fails for a reason unrelated to stock |
| PostgreSQL version | 17.12 | 18 | The course is graded on PostgreSQL 18 |

## Re-run commands

```bash
docker exec kloudkart-db psql -U kloudkart -d kloudkart -f /profiling/diagnosis.sql      > validation/post_<step>_diagnosis.txt
docker exec kloudkart-db psql -U kloudkart -d kloudkart -f /relationDATA/reconciliation.sql > validation/post_<step>_reconciliation.txt
DATABASE_URL=postgresql://kloudkart:kloudkart@localhost:5432/kloudkart python M03_Resources/race_test.py > validation/post_<step>_race_test.txt
```
