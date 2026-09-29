-- The native guide's closing information-delivery query: order counts by
-- customer nation / region and the business-vault priority tier.
-- Guide version joined DEV_DW.SALESMKT.dim1_customer, DEV_DW.CUSTSERV.fct_customer_order
-- and DEV_DW.CUSTSERV.dim1_order; here the same shape over ref()s.
--
-- Analyses compile but are never materialised:
--   dbt compile --select orders_by_region_tier
--   dbt show --select orders_by_region_tier [--target lz]

SELECT
    dc.REGION_NAME
  , dc.NATION_NAME
  , do.ORDER_PRIORITY_BUCKET
  , COUNT(*)                    AS CNT_ORDERS
FROM {{ ref('fct_customer_order') }}  fct
JOIN {{ ref('dim_customer') }}        dc ON dc.CUSTOMER_ID = fct.CUSTOMER_ID
JOIN {{ ref('dim_order') }}           do ON do.ORDER_ID    = fct.ORDER_ID
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3
