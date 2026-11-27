-- Kloud Kart: timings for every report query. Run once before solution/05_indexes.sql and once after.
--   docker exec kloudkart-db psql -U kloudkart -d kloudkart -f /performance/measure.sql > performance/<before|after>.txt
-- Each block prints the full plan (for reading node by node) ending in "Execution Time".
-- Report date fixed at 2026-08-31 (the last full month of the extract) so runs are comparable.

\set ON_ERROR_STOP on
\pset pager off

\echo '### A. NAIVE Monday report: one subquery per figure per customer (14 per customer), first 200 customers'
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.customer_id,
       (SELECT sum(o.total_amount) FROM orders o
        WHERE o.customer_id = c.customer_id AND o.status IN ('completed', 'shipped')) AS total_spent,
       (SELECT count(*) FROM orders o
        WHERE o.customer_id = c.customer_id AND o.status IN ('completed', 'shipped')) AS order_count,
       (SELECT array_agg((SELECT coalesce(sum(o.total_amount), 0) FROM orders o
                          WHERE o.customer_id = c.customer_id AND o.status IN ('completed', 'shipped')
                            AND date_trunc('month', o.order_date) = m) ORDER BY m)
        FROM generate_series(timestamp '2025-09-01', timestamp '2026-08-01', interval '1 month') m) AS monthly
FROM customers c
WHERE c.customer_id IN (SELECT customer_id FROM customers ORDER BY customer_id LIMIT 200);

\echo '### B. Monday report, ALL customers, one pass (monday_report)'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM monday_report('2026-08-31');

\echo '### C. Top 100'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM monday_report('2026-08-31') WHERE spend_rank <= 100;

\echo '### D. Running total, every counted order'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM v_customer_running_total;

\echo '### E. Running total, one customer'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM v_customer_running_total WHERE customer_id = 100001;

\echo '### F. Low-stock rollup, whole tree'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM low_stock_rollup();

\echo '### G. Stock trail, one product'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM v_stock_trail WHERE product_id = 5005;
