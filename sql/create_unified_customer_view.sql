-- Unified customers view: one row per customer that exists in BOTH AutoCare and Stripe.
-- AutoCare is the source of truth for customer identity and contact info.
-- Stripe provides payment/address/subscription data only.
-- Replace PROJECT_ID with your GCP project ID before running.
--
-- NOTE: The Cloud Function (refresh_unified_customers) runs this same logic inline
-- to materialize unified.customers as a table. This view is for ad-hoc querying only.

CREATE OR REPLACE VIEW `PROJECT_ID.stripe_processed.unified_customers` AS
WITH
  stripe_subs AS (
    SELECT
      customer_id,
      ARRAY_AGG(STRUCT(
        subscription_id,
        status            AS sub_status,
        plan_name, plan_id,
        product_id        AS stripe_product_id,
        amount            AS sub_amount,
        currency          AS sub_currency,
        subscription_interval,
        interval_count,
        current_period_start,
        current_period_end,
        cancel_at_period_end,
        canceled_at,
        ended_at,
        collection_method,
        created           AS sub_created,
        updated_at        AS sub_updated_at
      ) ORDER BY created DESC) AS stripe_subscriptions
    FROM `PROJECT_ID.stripe_processed.subscriptions`
    GROUP BY customer_id
  ),
  stripe_product_ids AS (
    SELECT
      customer_id,
      ARRAY_AGG(DISTINCT product_id IGNORE NULLS) AS stripe_product_ids
    FROM `PROJECT_ID.stripe_processed.subscriptions`
    GROUP BY customer_id
  ),
  -- Current (latest active, then latest) AutoCare tier per customer
  current_tier AS (
    SELECT
      sub.billing_id,
      t.product_id  AS current_tier_product_id,
      t.name        AS current_tier_name,
      t.product_key AS current_tier_key,
      t.perks       AS current_tier_perks
    FROM (
      SELECT
        billing_id, product_id,
        ROW_NUMBER() OVER (
          PARTITION BY billing_id
          ORDER BY CASE WHEN status = 'active' THEN 0 ELSE 1 END, updated_at DESC
        ) AS rn
      FROM `PROJECT_ID.autocare_processed.marketing_subscriptions`
    ) sub
    LEFT JOIN `PROJECT_ID.autocare_processed.tiers` t ON t.product_id = sub.product_id
    WHERE sub.rn = 1
  ),
  ac_subs AS (
    SELECT
      sub.billing_id,
      ARRAY_AGG(STRUCT(
        sub.subscription_id,
        sub.status        AS sub_status,
        sub.product_id    AS sub_product_id,
        sub.car_ids       AS sub_car_ids,
        t.name            AS tier_name,
        t.product_key     AS tier_key,
        t.description     AS tier_description,
        t.perks           AS tier_perks,
        t.taxable_amount  AS tier_taxable_amount,
        sub.updated_at    AS sub_updated_at,
        sub.ingested_at   AS sub_ingested_at
      ) ORDER BY sub.subscription_id) AS autocare_subscriptions
    FROM `PROJECT_ID.autocare_processed.marketing_subscriptions` sub
    LEFT JOIN `PROJECT_ID.autocare_processed.tiers` t ON t.product_id = sub.product_id
    GROUP BY sub.billing_id
  ),
  ac_cars AS (
    SELECT
      billing_id,
      ARRAY_AGG(STRUCT(
        car_id, make, model, year, license_plate, color, vin,
        updated_at AS car_updated_at, ingested_at AS car_ingested_at
      ) ORDER BY car_id) AS cars
    FROM `PROJECT_ID.autocare_processed.marketing_cars`
    GROUP BY billing_id
  ),
  ac_sessions AS (
    SELECT
      client_id,
      ARRAY_AGG(STRUCT(
        session_id, session_date, session_type, session_description,
        location_id, location_name, location_is_active,
        updated_at AS session_updated_at, ingested_at AS session_ingested_at
      ) ORDER BY session_date DESC) AS sessions
    FROM `PROJECT_ID.autocare_processed.marketing_sessions`
    GROUP BY client_id
  )
SELECT
  -- Primary identifiers (AutoCare is source of truth)
  ac.client_id                                        AS autocare_client_id,
  ac.billing_id,

  -- Customer profile — all from AutoCare
  ac.email,
  ac.first_name,
  ac.last_name,
  TRIM(CONCAT(
    COALESCE(ac.first_name, ''), ' ', COALESCE(ac.last_name, '')
  ))                                                  AS full_name,
  ac.phone_number,
  ac.customer_created_date                            AS autocare_customer_since,
  ac.updated_at                                       AS autocare_updated_at,
  ac.ingested_at                                      AS autocare_ingested_at,

  -- Stripe verification fields (no contact info duplication)
  s.customer_id                                       AS stripe_customer_id,
  s.created                                           AS stripe_customer_since,
  s.currency                                          AS stripe_currency,
  s.email                                             AS stripe_email,
  s.name                                              AS stripe_name,
  s.description                                       AS stripe_description,
  s.phone                                             AS stripe_phone,
  s.address_line1, s.address_line2, s.address_city,
  s.address_state, s.address_postal_code, s.address_country,

  -- Current membership tier
  ct.current_tier_product_id,
  ct.current_tier_name,
  ct.current_tier_key,
  ct.current_tier_perks,

  -- Stripe data
  COALESCE(ss.stripe_subscriptions, [])               AS stripe_subscriptions,
  COALESCE(spids.stripe_product_ids, [])              AS stripe_product_ids,

  -- AutoCare arrays
  COALESCE(asubs.autocare_subscriptions, [])          AS autocare_subscriptions,
  COALESCE(cars.cars, [])                             AS cars,
  COALESCE(sess.sessions, [])                         AS sessions

-- AutoCare drives; INNER JOIN ensures only customers in BOTH systems appear
FROM `PROJECT_ID.autocare_processed.marketing_customers` ac
INNER JOIN `PROJECT_ID.stripe_processed.customers` s     ON s.customer_id     = ac.billing_id
LEFT JOIN  stripe_subs        ss                         ON ss.customer_id    = ac.billing_id
LEFT JOIN  stripe_product_ids spids                      ON spids.customer_id = ac.billing_id
LEFT JOIN  current_tier       ct                         ON ct.billing_id     = ac.billing_id
LEFT JOIN  ac_subs            asubs                      ON asubs.billing_id  = ac.billing_id
LEFT JOIN  ac_cars            cars                       ON cars.billing_id   = ac.billing_id
LEFT JOIN  ac_sessions        sess                       ON sess.client_id    = ac.client_id;
