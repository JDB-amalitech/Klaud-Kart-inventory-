-- Goal 4 · PROOF OF WHAT HAPPENED. Every stock change ends up in inventory_log, by construction.
--   record_movement()  the one way to restock, return, damage, correct or count stock: changes stock and
--                      writes the movement in the same transaction (sales go through place_order instead).
--   stock guard        a trigger that writes a 'correction' movement for ANY stock change made some other
--                      way (a manual UPDATE in a terminal), naming who did it. Nothing changes stock silently.
--   v_stock_trail      the auditor's view: every movement, the balance after it, the order and customer
--                      behind a sale, and who wrote it.
-- Writers that log their own movement set kloudkart.movement_logged for the length of their UPDATE only.

-- Stock guard -----------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION log_unrecorded_stock_change() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.stock_quantity IS DISTINCT FROM OLD.stock_quantity
       AND coalesce(current_setting('kloudkart.movement_logged', true), 'off') <> 'on' THEN
        INSERT INTO inventory_log (product_id, change_qty, reason, note)
        VALUES (NEW.product_id, NEW.stock_quantity - OLD.stock_quantity, 'correction',
                'direct stock change, not made through place_order or record_movement');
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS products_stock_guard ON products;
CREATE TRIGGER products_stock_guard
    AFTER UPDATE OF stock_quantity ON products
    FOR EACH ROW EXECUTE FUNCTION log_unrecorded_stock_change();

-- The supported way to move stock other than a sale -----------------------------------------------------
CREATE OR REPLACE FUNCTION record_movement(p_product_id bigint, p_change integer,
                                           p_reason text, p_note text DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
    v_found  boolean;
    v_log_id bigint;
BEGIN
    IF p_reason = 'sale' THEN
        RAISE EXCEPTION 'Sales must go through place_order, so every sale carries its order.';
    END IF;

    PERFORM set_config('kloudkart.movement_logged', 'on', true);
    UPDATE products SET stock_quantity = stock_quantity + p_change WHERE product_id = p_product_id;
    v_found := FOUND;
    PERFORM set_config('kloudkart.movement_logged', 'off', true);

    IF NOT v_found THEN
        RAISE EXCEPTION 'Unknown product %', p_product_id;
    END IF;

    INSERT INTO inventory_log (product_id, change_qty, reason, note)
    VALUES (p_product_id, p_change, p_reason, p_note)
    RETURNING log_id INTO v_log_id;
    RETURN v_log_id;
END $$;

-- The auditor's view ------------------------------------------------------------------------------------
-- balance_after: running sum of movements per product, in the order they happened (ties broken by log_id).
-- Filtering on product_id is pushed inside the window, so one product's trail reads only its own rows.
CREATE OR REPLACE VIEW v_stock_trail AS
SELECT l.log_id,
       l.created_at,
       l.product_id,
       p.product_name,
       l.reason,
       l.change_qty,
       sum(l.change_qty) OVER (PARTITION BY l.product_id ORDER BY l.created_at, l.log_id
                               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS balance_after,
       l.order_id,
       o.customer_id,
       l.created_by,
       l.note
FROM inventory_log l
JOIN products p ON p.product_id = l.product_id
LEFT JOIN orders o ON o.order_id = l.order_id;

COMMENT ON VIEW v_stock_trail IS 'Every stock movement with the balance after it. Last balance_after = what the log says is on hand.';
