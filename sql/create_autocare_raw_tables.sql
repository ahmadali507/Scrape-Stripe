-- AutoCare API raw data tables (mirrors Stripe raw pattern)
-- Run in BigQuery with dataset autocare_raw created first, e.g.:
-- bq mk -d autocare_raw

-- Tiers: one row per product from v1/marketing/tiers
CREATE TABLE IF NOT EXISTS autocare_raw.tiers_raw (
  id STRING NOT NULL,                    -- Stripe product ID (e.g. prod_xxx)
  json_data STRING NOT NULL,
  ingested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
OPTIONS(
  description="Raw JSON from AutoCare v1/marketing/tiers - one row per tier"
);

-- Marketing data: one row per item in v1/marketing/data (customers + sessions) — legacy, no longer written
CREATE TABLE IF NOT EXISTS autocare_raw.marketing_data_raw (
  id STRING NOT NULL,
  record_type STRING,
  json_data STRING NOT NULL,
  ingested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY DATE(ingested_at)
OPTIONS(
  description="Legacy: raw from v1/marketing/data. New sync uses stripe_customers_raw."
);

-- Stripe-linked customers: one row per record from v1/marketing/stripe-customers (cursor-based)
CREATE TABLE IF NOT EXISTS autocare_raw.stripe_customers_raw (
  id STRING NOT NULL,                    -- clientId or billingID
  json_data STRING NOT NULL,
  ingested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY DATE(ingested_at)
OPTIONS(
  description="Raw JSON from AutoCare v1/marketing/stripe-customers - Stripe-linked only, append-only"
);
