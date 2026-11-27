-- Inventory log. Run via diagnosis.sql (sets read-only).

-- L1 Direction of movement per reason (negative = stock out)
SELECT reason, count(*) AS entries,
       count(*) FILTER (WHERE change_qty > 0) AS stock_in,
       count(*) FILTER (WHERE change_qty < 0) AS stock_out,
       count(*) FILTER (WHERE change_qty = 0) AS no_change
FROM inventory_log GROUP BY 1 ORDER BY 2 DESC;

-- L2 Log headline counts, and what the notes say
SELECT count(*) FILTER (WHERE p.product_id IS NULL)       AS unknown_product,
       count(*) FILTER (WHERE l.created_at > now())       AS in_future,
       count(*) FILTER (WHERE l.created_at < p.created_at) AS before_product_created,
       count(l.note)                                      AS with_note,
       string_agg(DISTINCT l.note, ' | ')                 AS distinct_notes
FROM inventory_log l LEFT JOIN products p USING (product_id);

-- L3 Does stock on hand equal the log's net movement?
WITH net AS (SELECT product_id, sum(change_qty) AS log_net FROM inventory_log GROUP BY 1)
SELECT CASE sign(p.stock_quantity - n.log_net)
            WHEN 0 THEN 'stock = log' WHEN 1 THEN 'stock > log' ELSE 'stock < log' END AS comparison,
       count(*) AS products,
       max(abs(p.stock_quantity - n.log_net)) AS worst_gap
FROM products p JOIN net n USING (product_id)
GROUP BY 1 ORDER BY 2 DESC;

-- L4 When is a sale logged? Order lines by fulfilment vs. 'sale' log entries
SELECT CASE WHEN lower(btrim(o.status)) IN ('completed', 'complete', 'shipped')
            THEN 'order lines: fulfilled' ELSE 'order lines: ' || lower(btrim(o.status)) END AS source,
       count(*) AS entries, sum(oi.quantity) AS units
FROM order_items oi JOIN orders o USING (order_id)
GROUP BY 1
UNION ALL
SELECT 'log: sale entries', count(*), -sum(change_qty) FROM inventory_log WHERE reason = 'sale'
ORDER BY 2 DESC;
