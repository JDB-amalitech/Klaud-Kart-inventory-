-- Order items. Run via diagnosis.sql (sets read-only).

-- I1 Order item headline counts
SELECT count(*) FILTER (WHERE o.order_id IS NULL)                     AS unknown_order,
       count(*) - count(DISTINCT (oi.order_id, oi.product_id, oi.quantity, oi.unit_price))
                                                                      AS exact_duplicate_lines,
       count(*) FILTER (WHERE oi.quantity >= 999)                     AS extreme_quantity,
       count(*) FILTER (WHERE oi.unit_price IS NULL)                  AS null_price,
       count(*) FILTER (WHERE oi.unit_price = 0)                      AS zero_price,
       count(*) FILTER (WHERE oi.unit_price BETWEEN 0.01 AND p.price - 0.01)               AS below_current_price,
       count(*) FILTER (WHERE oi.unit_price > p.price)                AS above_current_price
FROM order_items oi
LEFT JOIN orders o   USING (order_id)
LEFT JOIN products p USING (product_id);

-- I2 The extreme-quantity lines
SELECT oi.order_id, oi.product_id, oi.quantity, oi.unit_price, o.status, o.total_amount
FROM order_items oi JOIN orders o USING (order_id)
WHERE oi.quantity >= 999
ORDER BY oi.quantity DESC;
