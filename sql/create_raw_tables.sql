-- Create raw data tables for storing complete JSON from Stripe API

-- Customers raw data
CREATE TABLE IF NOT EXISTS stripe_raw.customers_raw (
  id STRING NOT NULL,                    -- Stripe customer ID
  json_data STRING NOT NULL,             -- Complete JSON response from Stripe
  ingested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  created TIMESTAMP                      -- Stripe created timestamp (for partitioning)
)
PARTITION BY DATE(created)
CLUSTER BY id
OPTIONS(
  description="Raw JSON data for Stripe customers"
);

-- Subscriptions raw data
CREATE TABLE IF NOT EXISTS stripe_raw.subscriptions_raw (
  id STRING NOT NULL,                    -- Stripe subscription ID
  json_data STRING NOT NULL,             -- Complete JSON response from Stripe
  ingested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  created TIMESTAMP                      -- Stripe created timestamp (for partitioning)
)
PARTITION BY DATE(created)
CLUSTER BY id
OPTIONS(
  description="Raw JSON data for Stripe subscriptions"
);


