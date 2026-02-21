-- AutoCare processed tables (flattened, query-ready)

-- Tiers: one row per membership product
CREATE TABLE IF NOT EXISTS autocare_processed.tiers (
  product_id STRING NOT NULL,
  name STRING,
  description STRING,
  product_key STRING,                   -- basic, pro, connect
  metadata_order STRING,
  perks STRING,
  refund_required STRING,
  external_api_integration STRING,
  validation_rules STRING,
  validation_description STRING,
  taxable_amount STRING,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  ingested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
OPTIONS(
  description="Processed AutoCare membership tiers from v1/marketing/tiers"
);

-- Marketing customers: one row per distinct customer (clientId/billingID)
CREATE TABLE IF NOT EXISTS autocare_processed.marketing_customers (
  client_id STRING NOT NULL,            -- AutoCare internal ID
  billing_id STRING,                    -- Stripe customer ID (cus_*) - JOIN key to Stripe
  email STRING,
  first_name STRING,
  last_name STRING,
  phone_number STRING,
  customer_created_date TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  ingested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY billing_id, client_id, email
OPTIONS(
  description="Processed AutoCare customers from v1/marketing/data - link via billing_id to Stripe"
);

-- Marketing subscriptions: one row per subscription (nested under customers)
CREATE TABLE IF NOT EXISTS autocare_processed.marketing_subscriptions (
  subscription_id STRING NOT NULL,
  client_id STRING,
  billing_id STRING,
  status STRING,
  product_id STRING,                    -- links to tiers.product_id
  car_ids STRING,                       -- JSON array of car IDs
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  ingested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY subscription_id, billing_id, client_id
OPTIONS(
  description="Processed AutoCare subscriptions from v1/marketing/data"
);

-- Marketing sessions: one row per usage/session event
CREATE TABLE IF NOT EXISTS autocare_processed.marketing_sessions (
  session_id STRING NOT NULL,
  client_id STRING,
  session_date TIMESTAMP,
  session_type STRING,
  session_description STRING,
  location_id STRING,
  location_name STRING,
  location_is_active BOOLEAN,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  ingested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY DATE(session_date)
CLUSTER BY session_id, client_id
OPTIONS(
  description="Processed AutoCare session/usage events from v1/marketing/data"
);

-- Marketing cars: one row per car (nested under customers in API)
CREATE TABLE IF NOT EXISTS autocare_processed.marketing_cars (
  car_id STRING NOT NULL,
  client_id STRING,
  billing_id STRING,
  json_data STRING,                       -- full car object for all fields
  make STRING,
  model STRING,
  year INT64,
  license_plate STRING,
  color STRING,
  vin STRING,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  ingested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY car_id, billing_id, client_id
OPTIONS(
  description="Processed AutoCare cars from v1/marketing/data - full payload in json_data"
);
