-- BI table: flat, denormalized customer 360 snapshot for Looker/Tableau/Metabase/Power BI.
-- One row per customer. Built from unified.customers + CTEs for latest entities and counts.
-- PROJECT_ID is replaced at runtime by the Cloud Function.

CREATE OR REPLACE TABLE `PROJECT_ID.bi.unified_customer_360_snapshot`
PARTITION BY DATE(customer_since)
CLUSTER BY customer_id, email, current_tier_key
OPTIONS(description = 'Flat customer 360 for BI tools - refreshed after Stripe + AutoCare sync')
AS
WITH
  uc AS (
    SELECT
      customer_id,
      autocare_client_id,
      email,
      name,
      phone,
      stripe_created AS customer_since,
      autocare_customer_created_date AS autocare_created_at,
      GREATEST(COALESCE(stripe_updated_at, TIMESTAMP('1970-01-01')), COALESCE(autocare_updated_at, TIMESTAMP('1970-01-01'))) AS last_synced_at
    FROM `PROJECT_ID.unified.customers`
  ),
  latest_stripe_sub AS (
    SELECT
      customer_id,
      subscription_id AS latest_stripe_subscription_id,
      status AS latest_stripe_sub_status,
      plan_name AS latest_plan_name,
      amount AS latest_plan_amount,
      currency AS latest_plan_currency,
      subscription_interval AS latest_plan_interval,
      current_period_start AS latest_period_start,
      current_period_end AS latest_period_end,
      cancel_at_period_end AS canceling_at_period_end,
      created AS latest_stripe_sub_created_at
    FROM (
      SELECT
        customer_id,
        subscription_id,
        status,
        plan_name,
        amount,
        currency,
        subscription_interval,
        current_period_start,
        current_period_end,
        cancel_at_period_end,
        created,
        ROW_NUMBER() OVER (
          PARTITION BY customer_id
          ORDER BY (CASE WHEN status = 'active' THEN 0 ELSE 1 END), created DESC
        ) AS rn
      FROM `PROJECT_ID.stripe_processed.subscriptions`
    )
    WHERE rn = 1
  ),
  latest_autocare_sub AS (
    SELECT
      s.billing_id,
      s.subscription_id AS latest_autocare_subscription_id,
      s.status AS latest_autocare_sub_status,
      t.product_id AS current_tier_product_id,
      t.name AS current_tier_name,
      t.product_key AS current_tier_key,
      t.perks AS current_tier_perks,
      s.updated_at AS latest_autocare_sub_updated_at
    FROM (
      SELECT
        billing_id,
        subscription_id,
        status,
        product_id,
        updated_at,
        ROW_NUMBER() OVER (PARTITION BY billing_id ORDER BY updated_at DESC) AS rn
      FROM `PROJECT_ID.autocare_processed.marketing_subscriptions`
    ) s
    LEFT JOIN `PROJECT_ID.autocare_processed.tiers` t ON t.product_id = s.product_id
    WHERE s.rn = 1
  ),
  latest_session AS (
    SELECT
      client_id,
      session_id AS latest_session_id,
      DATE(session_date) AS latest_session_date,
      session_type AS latest_session_type,
      session_description AS latest_session_description,
      location_id AS latest_session_location_id,
      location_name AS latest_session_location
    FROM (
      SELECT
        client_id,
        session_id,
        session_date,
        session_type,
        session_description,
        location_id,
        location_name,
        ROW_NUMBER() OVER (PARTITION BY client_id ORDER BY session_date DESC, session_id DESC) AS rn
      FROM `PROJECT_ID.autocare_processed.marketing_sessions`
    )
    WHERE rn = 1
  ),
  latest_car AS (
    SELECT
      billing_id,
      car_id AS latest_car_id,
      make AS latest_car_make,
      model AS latest_car_model,
      year AS latest_car_year,
      license_plate AS latest_car_license_plate,
      color AS latest_car_color,
      vin AS latest_car_vin
    FROM (
      SELECT
        billing_id,
        car_id,
        make,
        model,
        year,
        license_plate,
        color,
        vin,
        ROW_NUMBER() OVER (PARTITION BY billing_id ORDER BY updated_at DESC) AS rn
      FROM `PROJECT_ID.autocare_processed.marketing_cars`
    )
    WHERE rn = 1
  ),
  subscription_counts AS (
    SELECT
      customer_id,
      COUNT(*) AS total_stripe_subscriptions,
      COUNTIF(status = 'active') AS active_stripe_subscriptions,
      COUNTIF(status = 'canceled') AS canceled_stripe_subscriptions
    FROM `PROJECT_ID.stripe_processed.subscriptions`
    GROUP BY customer_id
  ),
  autocare_sub_counts AS (
    SELECT
      billing_id,
      COUNT(*) AS total_autocare_subscriptions,
      COUNT(DISTINCT product_id) AS distinct_tiers_used
    FROM `PROJECT_ID.autocare_processed.marketing_subscriptions`
    GROUP BY billing_id
  ),
  session_counts AS (
    SELECT
      client_id,
      COUNT(*) AS total_sessions,
      MIN(DATE(session_date)) AS first_session_date,
      MAX(DATE(session_date)) AS last_session_date
    FROM `PROJECT_ID.autocare_processed.marketing_sessions`
    GROUP BY client_id
  ),
  car_counts AS (
    SELECT
      billing_id,
      COUNT(*) AS total_cars
    FROM `PROJECT_ID.autocare_processed.marketing_cars`
    GROUP BY billing_id
  )
SELECT
  uc.customer_id,
  uc.autocare_client_id,
  uc.email,
  uc.name,
  uc.phone,
  uc.customer_since,
  uc.autocare_created_at,
  CASE
    WHEN ls.latest_stripe_sub_status = 'active' THEN 'Active'
    WHEN ls.latest_stripe_sub_status = 'past_due' THEN 'Past Due'
    WHEN ls.latest_stripe_sub_status = 'canceled' THEN 'Churned'
    ELSE 'No Subscription'
  END AS customer_status,
  ls.latest_stripe_subscription_id,
  ls.latest_stripe_sub_status,
  ls.latest_plan_name,
  ls.latest_plan_amount,
  ls.latest_plan_currency,
  ls.latest_plan_interval,
  ls.latest_period_start,
  ls.latest_period_end,
  ls.canceling_at_period_end,
  ls.latest_stripe_sub_created_at,
  COALESCE(sc.total_stripe_subscriptions, 0) AS total_stripe_subscriptions,
  COALESCE(sc.active_stripe_subscriptions, 0) AS active_stripe_subscriptions,
  COALESCE(sc.canceled_stripe_subscriptions, 0) AS canceled_stripe_subscriptions,
  las.latest_autocare_subscription_id,
  las.latest_autocare_sub_status,
  las.current_tier_product_id,
  las.current_tier_name,
  las.current_tier_key,
  las.current_tier_perks,
  las.latest_autocare_sub_updated_at,
  COALESCE(ascnt.total_autocare_subscriptions, 0) AS total_autocare_subscriptions,
  COALESCE(ascnt.distinct_tiers_used, 0) AS distinct_tiers_used,
  lses.latest_session_id,
  lses.latest_session_date,
  lses.latest_session_type,
  lses.latest_session_description,
  lses.latest_session_location_id,
  lses.latest_session_location,
  COALESCE(sescnt.total_sessions, 0) AS total_sessions,
  sescnt.first_session_date,
  sescnt.last_session_date,
  lc.latest_car_id,
  lc.latest_car_make,
  lc.latest_car_model,
  lc.latest_car_year,
  lc.latest_car_license_plate,
  lc.latest_car_color,
  lc.latest_car_vin,
  COALESCE(cc.total_cars, 0) AS total_cars,
  uc.last_synced_at
FROM uc
LEFT JOIN latest_stripe_sub ls ON ls.customer_id = uc.customer_id
LEFT JOIN latest_autocare_sub las ON las.billing_id = uc.customer_id
LEFT JOIN latest_session lses ON lses.client_id = uc.autocare_client_id
LEFT JOIN latest_car lc ON lc.billing_id = uc.customer_id
LEFT JOIN subscription_counts sc ON sc.customer_id = uc.customer_id
LEFT JOIN autocare_sub_counts ascnt ON ascnt.billing_id = uc.customer_id
LEFT JOIN session_counts sescnt ON sescnt.client_id = uc.autocare_client_id
LEFT JOIN car_counts cc ON cc.billing_id = uc.customer_id;
