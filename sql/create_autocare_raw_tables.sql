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

-- Marketing data: one row per item in v1/marketing/data (customers + sessions)
CREATE TABLE IF NOT EXISTS autocare_raw.marketing_data_raw (
  id STRING NOT NULL,                    -- clientId, sessionId, or row index
  record_type STRING,                    -- 'customer' | 'session'
  json_data STRING NOT NULL,
  ingested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY DATE(ingested_at)
OPTIONS(
  description="Raw JSON from AutoCare v1/marketing/data - mixed customer and session records"
);
