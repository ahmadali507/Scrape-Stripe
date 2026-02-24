-- BI table: flat, denormalized customer 360 snapshot for Looker/Tableau/Metabase/Power BI.
-- One row per customer. Built from unified.customers + CTEs for latest entities and counts.
-- Replace PROJECT_ID with your GCP project ID before running.

CREATE OR REPLACE TABLE `PROJECT_ID.bi.unified_customer_360_snapshot`
PARTITION BY DATE(autocare_customer_since)
CLUSTER BY autocare_client_id, billing_id, current_tier_key
OPTIONS(description = 'Flat customer 360 for BI tools - AutoCare is source of truth, Stripe verified - refreshed after sync')
AS
WITH
  -- Base: read from unified.customers (already INNER JOINed AutoCare + Stripe)
  uc AS (
    SELECT
      autocare_client_id,
      billing_id,
      email,
      first_name,
      last_name,
      full_name,
      phone_number,
      DATE(autocare_customer_since)   AS autocare_customer_since,
      DATE(stripe_customer_since)     AS stripe_customer_since,
      address_line1,
      address_city,
      address_state,
      address_country,
      address_postal_code,
      -- Current tier already derived in unified.customers
      current_tier_product_id,
      current_tier_name,
      current_tier_key,
      current_tier_perks,
      stripe_product_ids,
      autocare_updated_at             AS last_synced_at
    FROM `PROJECT_ID.unified.customers`
  ),
  -- Latest Stripe subscription (active first, then most recently created)
  latest_stripe_sub AS (
    SELECT
      customer_id,
      subscription_id   AS latest_stripe_sub_id,
      status            AS latest_stripe_sub_status,
      plan_name         AS latest_stripe_plan_name,
      amount            AS latest_stripe_plan_amount,
      currency          AS latest_stripe_plan_currency,
      subscription_interval AS latest_stripe_plan_interval,
      current_period_end AS latest_stripe_period_end,
      cancel_at_period_end AS canceling_at_period_end,
      created           AS latest_stripe_sub_created_at
    FROM (
      SELECT *,
        ROW_NUMBER() OVER (
          PARTITION BY customer_id
          ORDER BY (CASE WHEN status = 'active' THEN 0 ELSE 1 END), created DESC
        ) AS rn
      FROM `PROJECT_ID.stripe_processed.subscriptions`
    )
    WHERE rn = 1
  ),
  -- Latest AutoCare subscription (active first, then most recently updated)
  latest_autocare_sub AS (
    SELECT
      billing_id,
      subscription_id   AS latest_autocare_sub_id,
      status            AS latest_autocare_sub_status,
      updated_at        AS latest_autocare_sub_updated_at
    FROM (
      SELECT *,
        ROW_NUMBER() OVER (
          PARTITION BY billing_id
          ORDER BY (CASE WHEN status = 'active' THEN 0 ELSE 1 END), updated_at DESC
        ) AS rn
      FROM `PROJECT_ID.autocare_processed.marketing_subscriptions`
    )
    WHERE rn = 1
  ),
  -- Latest session per customer
  latest_session AS (
    SELECT
      client_id,
      session_id        AS latest_session_id,
      DATE(session_date) AS latest_session_date,
      session_type      AS latest_session_type,
      session_description AS latest_session_description,
      location_name     AS latest_session_location
    FROM (
      SELECT *,
        ROW_NUMBER() OVER (
          PARTITION BY client_id ORDER BY session_date DESC, session_id DESC
        ) AS rn
      FROM `PROJECT_ID.autocare_processed.marketing_sessions`
    )
    WHERE rn = 1
  ),
  -- Most recently updated car per customer
  latest_car AS (
    SELECT
      billing_id,
      make   AS latest_car_make,
      model  AS latest_car_model,
      year   AS latest_car_year,
      license_plate AS latest_car_license_plate
    FROM (
      SELECT *,
        ROW_NUMBER() OVER (PARTITION BY billing_id ORDER BY updated_at DESC) AS rn
      FROM `PROJECT_ID.autocare_processed.marketing_cars`
    )
    WHERE rn = 1
  ),
  -- Stripe subscription counts
  stripe_sub_counts AS (
    SELECT
      customer_id,
      COUNT(*)                        AS total_stripe_subscriptions,
      COUNTIF(status = 'active')      AS active_stripe_subscriptions,
      COUNTIF(status = 'canceled')    AS canceled_stripe_subscriptions
    FROM `PROJECT_ID.stripe_processed.subscriptions`
    GROUP BY customer_id
  ),
  -- AutoCare subscription counts
  ac_sub_counts AS (
    SELECT
      billing_id,
      COUNT(*)                        AS total_autocare_subscriptions,
      COUNTIF(status = 'active')      AS active_autocare_subscriptions,
      COUNT(DISTINCT product_id)      AS distinct_tiers_used
    FROM `PROJECT_ID.autocare_processed.marketing_subscriptions`
    GROUP BY billing_id
  ),
  -- Session counts
  session_counts AS (
    SELECT
      client_id,
      COUNT(*)                        AS total_sessions,
      MIN(DATE(session_date))         AS first_session_date,
      MAX(DATE(session_date))         AS last_session_date
    FROM `PROJECT_ID.autocare_processed.marketing_sessions`
    GROUP BY client_id
  ),
  -- Car counts
  car_counts AS (
    SELECT
      billing_id,
      COUNT(*)                        AS total_cars
    FROM `PROJECT_ID.autocare_processed.marketing_cars`
    GROUP BY billing_id
  )
SELECT
  -- Identity (AutoCare source of truth)
  uc.autocare_client_id,
  uc.billing_id,

  -- Customer profile (all from AutoCare)
  uc.email,
  uc.first_name,
  uc.last_name,
  uc.full_name,
  uc.phone_number,
  uc.autocare_customer_since,
  uc.stripe_customer_since,

  -- Address (from Stripe)
  uc.address_line1,
  uc.address_city,
  uc.address_state,
  uc.address_country,
  uc.address_postal_code,

  -- Current membership tier (from AutoCare)
  uc.current_tier_product_id,
  uc.current_tier_name,
  uc.current_tier_key,
  uc.current_tier_perks,

  -- Derived customer status from latest Stripe subscription
  CASE
    WHEN ls.latest_stripe_sub_status = 'active'   THEN 'Active'
    WHEN ls.latest_stripe_sub_status = 'past_due'  THEN 'Past Due'
    WHEN ls.latest_stripe_sub_status = 'canceled'  THEN 'Churned'
    ELSE 'No Stripe Subscription'
  END AS customer_status,

  -- Latest Stripe subscription
  ls.latest_stripe_sub_id,
  ls.latest_stripe_sub_status,
  ls.latest_stripe_plan_name,
  ls.latest_stripe_plan_amount,
  ls.latest_stripe_plan_currency,
  ls.latest_stripe_plan_interval,
  ls.latest_stripe_period_end,
  ls.canceling_at_period_end,
  ls.latest_stripe_sub_created_at,

  -- Stripe product IDs (array from unified.customers)
  uc.stripe_product_ids,

  -- Stripe subscription counts
  COALESCE(ssc.total_stripe_subscriptions, 0)    AS total_stripe_subscriptions,
  COALESCE(ssc.active_stripe_subscriptions, 0)   AS active_stripe_subscriptions,
  COALESCE(ssc.canceled_stripe_subscriptions, 0) AS canceled_stripe_subscriptions,

  -- Latest AutoCare subscription
  las.latest_autocare_sub_id,
  las.latest_autocare_sub_status,
  las.latest_autocare_sub_updated_at,

  -- AutoCare subscription counts
  COALESCE(asc_.total_autocare_subscriptions, 0)  AS total_autocare_subscriptions,
  COALESCE(asc_.active_autocare_subscriptions, 0) AS active_autocare_subscriptions,
  COALESCE(asc_.distinct_tiers_used, 0)           AS distinct_tiers_used,

  -- Latest session
  lses.latest_session_id,
  lses.latest_session_date,
  lses.latest_session_type,
  lses.latest_session_description,
  lses.latest_session_location,

  -- Session counts
  COALESCE(sescnt.total_sessions, 0)   AS total_sessions,
  sescnt.first_session_date,
  sescnt.last_session_date,

  -- Latest car
  lc.latest_car_make,
  lc.latest_car_model,
  lc.latest_car_year,
  lc.latest_car_license_plate,

  -- Car counts
  COALESCE(cc.total_cars, 0) AS total_cars,

  -- Metadata
  uc.last_synced_at,
  CURRENT_TIMESTAMP()        AS snapshot_at

FROM uc
LEFT JOIN latest_stripe_sub  ls    ON ls.customer_id  = uc.billing_id
LEFT JOIN latest_autocare_sub las  ON las.billing_id  = uc.billing_id
LEFT JOIN latest_session      lses ON lses.client_id  = uc.autocare_client_id
LEFT JOIN latest_car          lc   ON lc.billing_id   = uc.billing_id
LEFT JOIN stripe_sub_counts   ssc  ON ssc.customer_id = uc.billing_id
LEFT JOIN ac_sub_counts       asc_ ON asc_.billing_id = uc.billing_id
LEFT JOIN session_counts      sescnt ON sescnt.client_id = uc.autocare_client_id
LEFT JOIN car_counts          cc   ON cc.billing_id   = uc.billing_id;
