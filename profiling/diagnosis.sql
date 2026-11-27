-- Kloud Kart data diagnosis: entry point. Read-only; nothing is changed.
--   docker exec kloudkart-db psql -U kloudkart -d kloudkart -f /profiling/diagnosis.sql
-- Check IDs (P1, C1, O1, I1, L1...) match ADR/0002-data-diagnosis.md.

\set ON_ERROR_STOP on
\pset null '(null)'
SET default_transaction_read_only = on;

\echo '=== OVERVIEW: every column of every table'
SELECT c.table_name, c.column_name, c.data_type,
       (xpath('/row/total/text()', x))[1]::text::bigint     AS total,
       (xpath('/row/nulls/text()', x))[1]::text::bigint     AS nulls,
       (xpath('/row/distinct/text()', x))[1]::text::bigint  AS distinct_values,
       (xpath('/row/untrimmed/text()', x))[1]::text::bigint AS untrimmed
FROM information_schema.columns c,
     query_to_xml(format(
         'SELECT count(*) AS total, count(*) - count(%1$I) AS nulls, count(DISTINCT %1$I) AS "distinct",
                 count(*) FILTER (WHERE %1$I::text <> btrim(%1$I::text)) AS untrimmed FROM %2$I',
         c.column_name, c.table_name), false, true, '') AS x
WHERE c.table_schema = 'public'
ORDER BY c.table_name, c.ordinal_position;

\echo '=== OVERVIEW: constraints in place (raw load: primary keys only; foreign keys come from relationDATA)'
SELECT conrelid::regclass AS table_name, string_agg(pg_get_constraintdef(oid), '; ') AS constraints
FROM pg_constraint WHERE connamespace = 'public'::regnamespace GROUP BY 1;

\echo '=== PRODUCTS AND CATEGORIES'
\ir products.sql
\echo '=== CUSTOMERS'
\ir customers.sql
\echo '=== ORDERS'
\ir orders.sql
\echo '=== ORDER ITEMS'
\ir order_items.sql
\echo '=== INVENTORY LOG'
\ir inventory_log.sql
