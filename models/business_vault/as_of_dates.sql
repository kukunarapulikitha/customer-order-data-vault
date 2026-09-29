-- Daily spine of "as of" points for the PIT table: the end of each day from
-- the first customer satellite load up to today. End of day, so a PIT row for
-- day D reflects everything loaded during D.

{{ config(materialized='table') }}

WITH bounds AS (

    SELECT MIN(LOAD_DATETIME)::DATE AS FIRST_DAY
    FROM {{ ref('sat_customer_details') }}

),

days AS (

    SELECT DATEADD('day', ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, b.FIRST_DAY) AS DAY
    FROM bounds b, TABLE(GENERATOR(ROWCOUNT => 3660))

)

SELECT DATEADD('millisecond', -1, DATEADD('day', 1, DAY))::TIMESTAMP_NTZ AS AS_OF_DATE
FROM days
WHERE DAY <= CURRENT_DATE()
