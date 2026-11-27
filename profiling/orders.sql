-- Orders. Run via diagnosis.sql (sets read-only).

-- O1 Status spellings. clean_rows = rows a filter like status = 'completed' would actually match.
SELECT lower(btrim(status)) AS status, count(*) AS orders,
       count(*) FILTER (WHERE status = lower(btrim(status))) AS clean_rows,
       string_agg(DISTINCT '"' || status || '"', ' ') AS raw_spellings
FROM orders GROUP BY 1 ORDER BY 2 DESC;

-- O2 References and dates. extract_end = last day with a normal volume (100+ orders).
WITH extract_end AS (
    SELECT max(d) AS d FROM (SELECT order_date::date AS d FROM orders GROUP BY 1 HAVING count(*) >= 100) x
)
SELECT count(*) FILTER (WHERE c.customer_id IS NULL)                      AS unknown_customer,
       min(o.customer_id) FILTER (WHERE c.customer_id IS NULL) || '-' ||
       max(o.customer_id) FILTER (WHERE c.customer_id IS NULL)            AS unknown_id_range,
       (SELECT d FROM extract_end)                                        AS extract_end,
       count(*) FILTER (WHERE o.order_date::date > (SELECT d FROM extract_end)) AS after_extract_end,
       count(*) FILTER (WHERE o.order_date > now())                       AS in_future,
       count(*) FILTER (WHERE o.order_date < c.registered_at)             AS before_registration
FROM orders o LEFT JOIN customers c USING (customer_id);

-- O3 total_amount vs. its line items, grouped by the likely cause of the gap
WITH lines AS (
    SELECT order_id, sum(quantity * unit_price) AS items_total,
           count(*) > count(DISTINCT (product_id, quantity, unit_price)) AS duplicated_line,
           bool_or(coalesce(unit_price, 0) = 0)                          AS unpriced_line,
           bool_or(quantity >= 999)                                      AS extreme_quantity
    FROM order_items GROUP BY 1
)
SELECT CASE WHEN extreme_quantity THEN 'extreme quantity line'
            WHEN duplicated_line  THEN 'duplicated line'
            WHEN unpriced_line    THEN 'unpriced line'
            ELSE 'unexplained' END                       AS likely_cause,
       count(*)                                          AS orders,
       count(*) FILTER (WHERE total_amount * 2 = items_total) AS total_exactly_half,
       round(sum(total_amount - coalesce(items_total, 0)), 2) AS total_minus_items
FROM orders JOIN lines USING (order_id)
WHERE abs(total_amount - coalesce(items_total, 0)) > 0.01
GROUP BY 1 ORDER BY 2 DESC;
