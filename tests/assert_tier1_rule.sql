-- Tier-1 must mean: priority 1-URGENT or 2-HIGH AND total price >= 200,000.
-- Returns any business-vault row that is labelled Tier-1 but breaks that rule.

SELECT
    ORDER_HK
  , LOAD_DATETIME
  , O_ORDERPRIORITY
  , O_TOTALPRICE
  , ORDER_PRIORITY_BUCKET
FROM {{ ref('bv_sat_order') }}
WHERE ORDER_PRIORITY_BUCKET = 'Tier-1'
  AND (O_ORDERPRIORITY NOT IN ('1-URGENT', '2-HIGH')
       OR O_TOTALPRICE < 200000)
