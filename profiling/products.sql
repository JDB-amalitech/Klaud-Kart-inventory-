-- Products and the category tree. Run via diagnosis.sql (sets read-only).

-- P1 Category tree health. CYCLE stops the walk at a loop instead of running forever,
--    which is what a naive recursive low-stock rollup would do.
WITH RECURSIVE up AS (
    SELECT category_id AS start_id, category_id, parent_id, 1 AS depth FROM categories
    UNION ALL
    SELECT u.start_id, c.category_id, c.parent_id, u.depth + 1
    FROM up u JOIN categories c ON c.category_id = u.parent_id
) CYCLE category_id SET is_cycle USING path,
status AS (
    SELECT start_id,
           CASE WHEN bool_or(is_cycle)         THEN 'in a cycle'
                WHEN bool_or(parent_id IS NULL) THEN 'ok, depth ' || max(depth)
                ELSE 'parent missing' END AS tree_status
    FROM up GROUP BY start_id
)
SELECT tree_status, count(DISTINCT s.start_id) AS categories,
       count(p.product_id) AS products,
       array_agg(DISTINCT start_id) FILTER (WHERE tree_status NOT LIKE 'ok%') AS category_ids
FROM status s LEFT JOIN products p ON p.category_id = s.start_id
GROUP BY 1 ORDER BY 1;

-- P2 Product headline counts
SELECT count(*) FILTER (WHERE stock_quantity < 0)                            AS negative_stock,
       count(*) FILTER (WHERE stock_quantity = 0)                            AS zero_stock,
       count(*) FILTER (WHERE category_id IS NULL)                           AS no_category,
       count(*) FILTER (WHERE category_id IN (SELECT parent_id FROM categories)) AS on_non_leaf_category,
       count(DISTINCT stock_quantity)                                        AS distinct_stock_values,
       count(*) - count(DISTINCT lower(btrim(product_name)))                 AS repeated_names
FROM products;

-- P3 Negative stock vs. sales rank: one hot product, or spread across the catalogue?
WITH sales AS (
    SELECT product_id, sum(quantity) AS units_sold, rank() OVER (ORDER BY sum(quantity) DESC) AS sales_rank
    FROM order_items GROUP BY 1
)
SELECT p.product_id, p.product_name, p.stock_quantity, s.units_sold, s.sales_rank
FROM products p JOIN sales s USING (product_id)
WHERE p.stock_quantity < 0
ORDER BY s.sales_rank;
