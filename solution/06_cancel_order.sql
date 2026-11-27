-- Improvement beyond the brief · CANCEL AN ORDER AND GIVE ITS STOCK BACK.
-- Why: place_order now takes stock when an order is placed (that is what stops overselling). Without
-- this, every cancelled pending order would keep its units off the shelf forever: stock would drift
-- low, Nana would turn away buyers for stock he has, and the counts would stop matching reality again.
-- What it does, in one transaction: locks the order (two clerks cannot cancel it twice), marks it
-- cancelled, puts each line's units back, and writes a 'return' movement per line carrying the order_id,
-- so the auditor sees the sale and its reversal side by side.
-- Only pending orders can be cancelled here; shipped or completed goods come back as returns.

CREATE OR REPLACE FUNCTION cancel_order(p_order_id bigint)
RETURNS TABLE (success boolean, message text)
LANGUAGE plpgsql AS $$
DECLARE
    v_status text;
BEGIN
    SELECT o.status INTO v_status FROM orders o WHERE o.order_id = p_order_id FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT false, 'Unknown order.';
        RETURN;
    ELSIF v_status <> 'pending' THEN
        RETURN QUERY SELECT false, 'Only pending orders can be cancelled; this one is ' || v_status || '.';
        RETURN;
    END IF;

    UPDATE orders SET status = 'cancelled' WHERE order_id = p_order_id;

    PERFORM set_config('kloudkart.movement_logged', 'on', true);
    UPDATE products p
    SET    stock_quantity = p.stock_quantity + i.quantity
    FROM   (SELECT product_id, sum(quantity) AS quantity
            FROM order_items WHERE order_id = p_order_id GROUP BY product_id) i
    WHERE  p.product_id = i.product_id;
    PERFORM set_config('kloudkart.movement_logged', 'off', true);

    INSERT INTO inventory_log (product_id, change_qty, reason, order_id, note)
    SELECT product_id, sum(quantity), 'return', p_order_id, 'order cancelled before fulfilment'
    FROM order_items WHERE order_id = p_order_id
    GROUP BY product_id;

    RETURN QUERY SELECT true, 'Order cancelled; stock returned.';
END $$;

COMMENT ON FUNCTION cancel_order(bigint) IS
    'Cancels a pending order and returns its stock, logged against the order. The partner of place_order.';
