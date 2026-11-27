-- Kloud Kart: reconciliations, each measured by the KPI that tells Nana or Adwoa what is at stake.
-- Read-only. Why each KPI was chosen: ADR/0003. Shape: reconciliation | kpi | actual | target.
--   docker exec kloudkart-db psql -U kloudkart -d kloudkart -f /relationDATA/reconciliation.sql

SET default_transaction_read_only = on;

-- R1 Relationships (one row per ERD line).
--    match_rate_pct: share of references a join keeps; below 100 = rows silently dropped from reports.
--    value_at_risk:  the money on those dropped rows, i.e. how much the Monday report under-states.
--    null_refs are counted apart from orphans: "points at nothing" is not "points at something missing".
WITH r AS (
    SELECT 'orders -> customers' AS relationship, count(o.customer_id) AS refs, count(c.customer_id) AS matched,
           count(*) - count(o.customer_id) AS null_refs,
           sum(o.total_amount) FILTER (WHERE c.customer_id IS NULL) AS value_at_risk
    FROM orders o LEFT JOIN customers c USING (customer_id)
    UNION ALL
    SELECT 'order_items -> orders', count(oi.order_id), count(o.order_id), count(*) - count(oi.order_id),
           sum(oi.quantity * oi.unit_price) FILTER (WHERE o.order_id IS NULL)
    FROM order_items oi LEFT JOIN orders o USING (order_id)
    UNION ALL
    SELECT 'order_items -> products', count(oi.product_id), count(p.product_id), count(*) - count(oi.product_id),
           sum(oi.quantity * oi.unit_price) FILTER (WHERE p.product_id IS NULL)
    FROM order_items oi LEFT JOIN products p USING (product_id)
    UNION ALL
    SELECT 'inventory_log -> products', count(l.product_id), count(p.product_id), count(*) - count(l.product_id), NULL
    FROM inventory_log l LEFT JOIN products p USING (product_id)
    UNION ALL
    SELECT 'products -> categories', count(p.category_id), count(c.category_id), count(*) - count(p.category_id), NULL
    FROM products p LEFT JOIN categories c USING (category_id)
    UNION ALL
    SELECT 'categories -> parent', count(ch.parent_id), count(pa.category_id), count(*) - count(ch.parent_id), NULL
    FROM categories ch LEFT JOIN categories pa ON pa.category_id = ch.parent_id
)
SELECT relationship, refs, refs - matched AS orphans, null_refs,
       round(100.0 * matched / refs, 2) AS match_rate_pct, value_at_risk
FROM r;

-- R2 Order header vs. its lines (the "total spent" in the Monday report comes from one of these two).
WITH t AS (
    SELECT o.total_amount - coalesce(sum(oi.quantity * oi.unit_price), 0) AS diff
    FROM orders o JOIN order_items oi USING (order_id)
    GROUP BY o.order_id, o.total_amount
)
SELECT 'R2 order total vs lines' AS reconciliation, k.*
FROM (SELECT round(100.0 * count(*) FILTER (WHERE abs(diff) <= 0.01) / count(*), 2) AS pct,
             round(sum(abs(diff)), 2) AS abs_var, round(sum(diff), 2) AS net_var FROM t) x,
     LATERAL (VALUES ('orders reconciled %',        x.pct,     100),
                     ('absolute variance (GHS)',    x.abs_var, 0),
                     ('net variance (GHS)',         x.net_var, 0)) k(kpi, actual, target);

-- R3 Stock on hand vs. the inventory log (the number Nana sells against vs. the trail that should prove it).
WITH s AS (
    SELECT p.stock_quantity, coalesce(sum(l.change_qty), 0) AS log_net
    FROM products p LEFT JOIN inventory_log l USING (product_id)
    GROUP BY p.product_id, p.stock_quantity
)
SELECT 'R3 stock vs log' AS reconciliation, k.*
FROM (SELECT round(100.0 * count(*) FILTER (WHERE stock_quantity = log_net) / count(*), 2) AS accuracy,
             sum(abs(stock_quantity - log_net)) AS unit_var,
             count(*) FILTER (WHERE stock_quantity < 0) AS negative FROM s) x,
     LATERAL (VALUES ('stock accuracy %',               x.accuracy, 100),
                     ('absolute unit variance',          x.unit_var, 0),
                     ('products already oversold (<0)',  x.negative, 0),
                     ('units on pending orders, not deducted',
                      (SELECT sum(oi.quantity) FROM order_items oi JOIN orders o USING (order_id)
                       WHERE lower(btrim(o.status)) = 'pending'), 0)) k(kpi, actual, target);

-- R4 Fulfilled sales vs. 'sale' movements (every sale must leave a stock movement: the audit trail).
WITH f AS (
    SELECT count(*) AS lines, sum(oi.quantity) AS units
    FROM order_items oi JOIN orders o USING (order_id)
    WHERE lower(btrim(o.status)) IN ('completed', 'complete', 'shipped')
), m AS (
    SELECT count(*) AS entries, -sum(change_qty) AS units FROM inventory_log WHERE reason = 'sale'
)
SELECT 'R4 sales vs movements' AS reconciliation, k.*
FROM f, m,
     LATERAL (VALUES ('movement coverage %',          round(100.0 * m.entries / f.lines, 3), 100),
                     ('fulfilled lines with no movement', f.lines - m.entries,              0),
                     ('unit variance (sold - logged)',    f.units - m.units,                0)) k(kpi, actual, target);

-- R5 Accounts vs. people (one person should be one customer, or their spend and rank are split).
SELECT 'R5 accounts vs people' AS reconciliation, k.*
FROM (SELECT count(*) AS accounts, count(DISTINCT lower(btrim(email))) AS people FROM customers) x,
     LATERAL (VALUES ('duplicate account rate %', round(100.0 * (x.accounts - x.people) / x.accounts, 2), 0),
                     ('surplus accounts',          x.accounts - x.people,                                0)) k(kpi, actual, target);

-- R6 Products vs. what the category rollup can reach (the low-stock screen only sees reachable products).
WITH RECURSIVE up AS (
    SELECT category_id AS start_id, parent_id FROM categories
    UNION ALL
    SELECT u.start_id, c.parent_id FROM up u JOIN categories c ON c.category_id = u.parent_id
) CYCLE start_id, parent_id SET is_cycle USING path,
reachable AS (SELECT start_id FROM up WHERE parent_id IS NULL AND NOT is_cycle)
SELECT 'R6 products vs rollup' AS reconciliation, k.*
FROM (SELECT round(100.0 * count(*) FILTER (WHERE category_id IN (SELECT start_id FROM reachable)) / count(*), 2) AS pct,
             count(*) FILTER (WHERE category_id NOT IN (SELECT start_id FROM reachable) OR category_id IS NULL) AS missed
      FROM products) x,
     LATERAL (VALUES ('products covered by rollup %', x.pct,    100),
                     ('products invisible to rollup',  x.missed, 0)) k(kpi, actual, target);
