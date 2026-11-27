-- Kloud Kart: Nana's four goals, in dependency order.
-- Prerequisites, in order: fresh load -> relationDATA/relationship.sql -> cleaning/clean_all.sql -> schema/upgrade.sql
--   docker exec kloudkart-db psql -U kloudkart -d kloudkart -f /solution/solution_all.sql

\set ON_ERROR_STOP on
\echo '=== 01 audit trail (goal 4)'
\ir 01_audit_trail.sql
\echo '=== 02 place_order (goal 1)'
\ir 02_place_order.sql
\echo '=== 03 low-stock rollup (goal 3)'
\ir 03_low_stock_rollup.sql
\echo '=== 04 Monday report (goal 2)'
\ir 04_monday_report.sql
\echo '=== 05 indexes'
\ir 05_indexes.sql
