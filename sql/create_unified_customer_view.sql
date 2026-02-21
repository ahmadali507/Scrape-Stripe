-- Unified customers: one row per customer, no duplications.
-- Complete info: Stripe + AutoCare profile, cars, sessions, subscriptions with tiers.
-- Replace PROJECT_ID with your GCP project ID.

CREATE OR REPLACE VIEW `PROJECT_ID.stripe_processed.unified_customers` AS
WITH
  m AS (
    SELECT
      billing_id,
      client_id,
      email AS autocare_email,
      first_name AS autocare_first_name,
      last_name AS autocare_last_name,
      phone_number AS autocare_phone,
      customer_created_date AS autocare_customer_created_date,
      updated_at AS autocare_updated_at,
      ingested_at AS autocare_ingested_at
    FROM `PROJECT_ID.autocare_processed.marketing_customers`
  ),
  stripe_subs AS (
    SELECT
      customer_id,
      ARRAY_AGG(
        STRUCT(
          subscription_id,
          object_type AS sub_object_type,
          status AS sub_status,
          created AS sub_created,
          current_period_start,
          current_period_end,
          cancel_at_period_end,
          canceled_at,
          ended_at,
          currency AS sub_currency,
          amount AS sub_amount,
          subscription_interval,
          interval_count,
          plan_name,
          plan_id,
          product_id AS stripe_product_id,
          collection_method,
          updated_at AS sub_updated_at,
          ingested_at AS sub_ingested_at
        )
        ORDER BY created DESC
      ) AS stripe_subscriptions
    FROM `PROJECT_ID.stripe_processed.subscriptions`
    GROUP BY customer_id
  )
SELECT
  -- Stripe customer (all fields)
  c.customer_id,
  c.object_type AS stripe_object_type,
  c.email AS stripe_email,
  c.name AS stripe_name,
  c.description AS stripe_description,
  c.phone AS stripe_phone,
  c.created AS stripe_created,
  c.created_timestamp AS stripe_created_timestamp,
  c.address_line1,a
  c.address_line2,
  c.address_city,
  c.address_state,
  c.address_postal_code,
  c.address_country,
  c.currency,
  c.balance,
  c.delinquent,
  c.default_source,
  c.invoice_prefix,
  c.updated_at AS stripe_updated_at,
  c.ingested_at AS stripe_ingested_at,
  -- AutoCare customer (all fields, single row)
  m.client_id AS autocare_client_id,
  m.autocare_email,
  m.autocare_first_name,
  m.autocare_last_name,
  m.autocare_phone,
  m.autocare_customer_created_date,
  m.autocare_updated_at,
  m.autocare_ingested_at,
  -- Unified contact (no duplication)
  COALESCE(c.email, m.autocare_email) AS email,
  COALESCE(c.name, TRIM(CONCAT(COALESCE(m.autocare_first_name, ''), ' ', COALESCE(m.autocare_last_name, '')))) AS name,
  COALESCE(c.phone, m.autocare_phone) AS phone,
  -- Stripe subscriptions (all fields, array)
  COALESCE(ss.stripe_subscriptions, []) AS stripe_subscriptions,
  -- AutoCare cars (all fields, array, no duplication)
  COALESCE(
    (
      SELECT ARRAY_AGG(
        STRUCT(
          car.car_id,
          car.client_id AS car_client_id,
          car.billing_id AS car_billing_id,
          car.json_data AS car_json_data,
          car.make,
          car.model,
          car.year,
          car.license_plate,
          car.color,
          car.vin,
          car.updated_at AS car_updated_at,
          car.ingested_at AS car_ingested_at
        )
        ORDER BY car.car_id
      )
      FROM `PROJECT_ID.autocare_processed.marketing_cars` car
      WHERE car.billing_id = c.customer_id
    ),
    []
  ) AS cars,
  -- AutoCare sessions (all fields, array, no duplication)
  COALESCE(
    (
      SELECT ARRAY_AGG(
        STRUCT(
          s.session_id,
          s.client_id AS session_client_id,
          s.session_date,
          s.session_type,
          s.session_description,
          s.location_id,
          s.location_name,
          s.location_is_active,
          s.updated_at AS session_updated_at,
          s.ingested_at AS session_ingested_at
        )
        ORDER BY s.session_date DESC
      )
      FROM `PROJECT_ID.autocare_processed.marketing_sessions` s
      WHERE s.client_id = m.client_id
    ),
    []
  ) AS sessions,
  -- AutoCare subscriptions with full tier (all fields, array, no duplication)
  COALESCE(
    (
      SELECT ARRAY_AGG(
        STRUCT(
          sub.subscription_id,
          sub.client_id AS sub_client_id,
          sub.billing_id AS sub_billing_id,
          sub.status AS sub_status,
          sub.product_id AS sub_product_id,
          sub.car_ids AS sub_car_ids,
          sub.updated_at AS sub_updated_at,
          sub.ingested_at AS sub_ingested_at,
          t.product_id AS tier_product_id,
          t.name AS tier_name,
          t.description AS tier_description,
          t.product_key AS tier_product_key,
          t.metadata_order AS tier_order,
          t.perks AS tier_perks,
          t.refund_required AS tier_refund_required,
          t.external_api_integration AS tier_external_api_integration,
          t.validation_rules AS tier_validation_rules,
          t.validation_description AS tier_validation_description,
          t.taxable_amount AS tier_taxable_amount,
          t.updated_at AS tier_updated_at,
          t.ingested_at AS tier_ingested_at
        )
        ORDER BY sub.subscription_id
      )
      FROM `PROJECT_ID.autocare_processed.marketing_subscriptions` sub
      LEFT JOIN `PROJECT_ID.autocare_processed.tiers` t ON t.product_id = sub.product_id
      WHERE sub.billing_id = c.customer_id
    ),
    []
  ) AS autocare_subscriptions_with_tiers
FROM `PROJECT_ID.stripe_processed.customers` c
LEFT JOIN m ON m.billing_id = c.customer_id
LEFT JOIN stripe_subs ss ON ss.customer_id = c.customer_id;
