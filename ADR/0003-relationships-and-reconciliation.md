# 0003: Enforce the ERD relationships, and reconcile with business KPIs

- **Status:** Accepted
- **Date:** 2026-11-27
- **Files:** `relationDATA/relationship.sql` (schema change), `relationDATA/reconciliation.sql` (read-only)
- **Source:** `Diagrams/sales_erd_hierarchy.drawio`

## Context

The ERD sets out three levels of tables (parents, then children, then transactions), joined by six relationships. None of them is enforced in the database ([0002](0002-data-diagnosis.md), root cause), and finding 6 shows orphans already exist. Nana's team has to live with any schema change, and `race_test.py` must still pass unmodified.

## Decision 1: Add the six foreign keys as `NOT VALID`

| Relationship (ERD) | Constraint | Existing orphans |
|---|---|---|
| categories.parent_id → categories | `fk_categories_parent` | 1 |
| products.category_id → categories | `fk_products_category` | 0 (37 NULL) |
| orders.customer_id → customers | `fk_orders_customer` | 210 |
| order_items.order_id → orders | `fk_order_items_order` | 692 |
| order_items.product_id → products | `fk_order_items_product` | 0 |
| inventory_log.product_id → products | `fk_inventory_log_product` | 120 |

The ERD's dashed orders ↔ products line is left out: order_items already connects them, so a direct link would store the same fact twice.

| Choice | Why | Rejected alternative, and why |
|---|---|---|
| `NOT VALID` | Stops new orphans today without deleting evidence. Old orphans stay visible until a cleaning ADR decides their fate, then `VALIDATE CONSTRAINT` finishes the job. | **Plain FK:** fails to create while orphans exist. **Delete the orphans first:** destroys 665k of orders and 826k of line value before anyone has decided what they are. |
| `ON DELETE RESTRICT` | Sales and stock movements are the audit trail. Deleting a product or customer must not erase them. | **CASCADE:** one careless delete wipes order history. **SET NULL:** keeps the rows but loses who or what they were for. |
| Nullable FK columns | Root categories, uncategorised products and `race_test` fixtures (category NULL) are legitimate. | **NOT NULL:** would break the test and force fake categories. |
| No FK indexes yet | The report needs a measured before/after. Indexes are added and timed in the performance stage. | **Index now:** speeds things up with no baseline to prove it. |

**Verified:** new orphan orders and order lines are rejected, deleting a product with sales is blocked, and a product with a NULL category is accepted. The test ran inside a transaction that was rolled back.

**Cost to Nana if wrong:**
- Any process that today writes orders for unknown customers will start failing loudly instead of silently. That is the intent, but it should be announced to his team.
- Under flash-sale load, every order-line insert briefly takes a share lock on its product row to check the key. `place_order` already holds that row, so this adds no extra waiting.

## Decision 2: Six reconciliations, each with the KPI that matches what the business reads

A reconciliation compares two records that should agree. Each KPI is chosen so the number answers "what does this cost Nana or Adwoa?", not just "how many rows are wrong?" (the costing method in [0002](0002-data-diagnosis.md)).

| # | Reconciles | KPI | Result | Target | Why this KPI |
|---|---|---|---|---|---|
| R1 | Each child to its parent (six ERD lines) | **Match rate %**, **value at risk (GHS)** | orders → customers 99.87% (665,181 at risk); order_items → orders 99.79% (826,328 at risk); log → products 99.96%; category → parent 98.85% | 100%, 0 | A join keeps only matched rows, so match rate is the share of data the report actually sees. Value at risk turns the gap into money the Monday report under-states. NULL references are counted separately: "no parent" is not "missing parent". |
| R2 | Order total to the sum of its lines | **Orders reconciled %**, **absolute variance**, **net variance (GHS)** | 98.48%; 5,291,592 absolute; −3,400,694 net | 100%, 0, 0 | "Total spent" comes from one of these two sources. The % shows how often they disagree. The absolute variance shows how much money depends on which source Adwoa uses. The net variance shows the direction: line items run higher, because of duplicate lines and 999/9999 quantities. |
| R3 | Stock on hand to the inventory log's net movement | **Stock accuracy %**, **absolute unit variance**, **oversold products**, **units on pending orders not deducted** | 96.42%; 2,553 units; 14; 63,413 | 100%, 0, 0, 0 | Accuracy % is the share of the catalogue whose sellable number can be proven from the trail, which directly measures "stock counts I can trust". Oversold products count the damage already done. Pending units show how far stock on hand overstates what can really be sold, which is the flash-sale risk. |
| R4 | Fulfilled order lines to `sale` movements | **Movement coverage %**, **lines with no movement**, **unit variance** | 99.993%; 18; 3,067 units | 100%, 0, 0 | Nana asked for a trail of every movement, so coverage % is the audit-trail completeness rate. "Lines with no movement" is the count an auditor would flag. The unit variance is mostly the three 999-quantity lines (2,997 units). |
| R5 | Customer accounts to people (normalised email) | **Duplicate account rate %**, **surplus accounts** | 1.32%; 535 | 0%, 0 | Per-customer totals, the running total and the top 100 all assume one person is one account. The rate shows how much of the customer base is split. |
| R6 | Products to what the category rollup can reach | **Products covered by rollup %**, **products invisible** | 98.93%; 43 (37 uncategorised + 6 in the 9001/9002 loop) | 100%, 0 | The low-stock screen can only warn about products it can reach through the tree. Coverage % is the share of stock the screen can actually see. |

Rejected KPIs:
- **Raw row counts on their own:** they don't rank by cost. The 692 orphan lines matter more than the 1,314 untrimmed emails.
- **Averages per order:** order values are skewed (median 690, mean 3,056), so an average hides where the money is.

## Consequences

- Re-running `reconciliation.sql` after each cleaning step should move every KPI toward its target. That is the proof a fix worked.
- Once a KPI reaches 100% for a relationship, run `ALTER TABLE … VALIDATE CONSTRAINT …` for it.
- R3 and R4 become ongoing health checks after `place_order` exists. Every sale it records must keep both at 100% for new orders.
