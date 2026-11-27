-- Goal 3 · LOW-STOCK VISIBILITY, rolled up through the category tree.
-- Decisions:
--   low stock      stock_quantity <= threshold (default 5 units, a parameter); out of stock = 0.
--   rolled up      a category's figures INCLUDE every product beneath it, at any depth.
--   no double count each product is counted once per ancestor (via its ancestor list), never once per path.
--   any depth      recursive walk from the roots; no level is hard-coded. CYCLE stops the walk at a loop
--                  instead of running forever, should marketing ever create one again.
-- Proof of no double counting: the top-level rows add up to the number of low-stock products (README).

CREATE OR REPLACE FUNCTION low_stock_rollup(p_threshold integer DEFAULT 5)
RETURNS TABLE (category_id integer, category_path text, depth integer,
               products bigint, low_stock bigint, out_of_stock bigint, low_stock_pct numeric)
LANGUAGE sql STABLE AS $$
    WITH RECURSIVE tree AS (
        SELECT c.category_id, c.category_name::text AS category_path, 1 AS depth,
               ARRAY[c.category_id] AS ancestors
        FROM categories c
        WHERE c.parent_id IS NULL
        UNION ALL
        SELECT c.category_id, t.category_path || ' > ' || c.category_name, t.depth + 1,
               t.ancestors || c.category_id
        FROM categories c
        JOIN tree t ON c.parent_id = t.category_id
    ) CYCLE category_id SET is_cycle USING walk,
    product_ancestor AS (            -- one row per (product, every category above it including its own)
        SELECT p.product_id, p.stock_quantity, a.ancestor_id
        FROM products p
        JOIN tree t ON t.category_id = p.category_id AND NOT t.is_cycle
        CROSS JOIN LATERAL unnest(t.ancestors) AS a(ancestor_id)
    )
    SELECT t.category_id, t.category_path, t.depth,
           count(pa.product_id)                                       AS products,
           count(pa.product_id) FILTER (WHERE pa.stock_quantity <= p_threshold) AS low_stock,
           count(pa.product_id) FILTER (WHERE pa.stock_quantity = 0)  AS out_of_stock,
           round(100.0 * count(pa.product_id) FILTER (WHERE pa.stock_quantity <= p_threshold)
                 / nullif(count(pa.product_id), 0), 1)                AS low_stock_pct
    FROM tree t
    LEFT JOIN product_ancestor pa ON pa.ancestor_id = t.category_id
    WHERE NOT t.is_cycle
    GROUP BY t.category_id, t.category_path, t.depth
    ORDER BY t.category_path;
$$;

-- At a glance, with the default threshold.
CREATE OR REPLACE VIEW v_low_stock_rollup AS
SELECT * FROM low_stock_rollup();

-- The products behind the numbers, with where they sit in the tree.
CREATE OR REPLACE VIEW v_low_stock_products AS
SELECT p.product_id, p.product_name, p.stock_quantity, r.category_path
FROM products p
JOIN v_low_stock_rollup r ON r.category_id = p.category_id
WHERE p.stock_quantity <= 5
ORDER BY p.stock_quantity, r.category_path, p.product_name;

COMMENT ON FUNCTION low_stock_rollup(integer) IS
    'Products, low-stock and out-of-stock counts per category, including everything beneath it. Threshold in units.';
