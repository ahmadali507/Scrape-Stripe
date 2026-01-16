-- Create processed tables with flattened schema for easy querying

-- Customers processed table
CREATE TABLE IF NOT EXISTS stripe_processed.customers (
  customer_id STRING NOT NULL,
  object_type STRING,
  email STRING,
  name STRING,
  description STRING,
  phone STRING,
  created TIMESTAMP,
  created_timestamp INT64,
  
  -- Address information
  address_line1 STRING,
  address_line2 STRING,
  address_city STRING,
  address_state STRING,
  address_postal_code STRING,
  address_country STRING,
  
  -- Billing information
  currency STRING,
  balance INT64,
  delinquent BOOLEAN,
  
  -- Metadata
  default_source STRING,
  invoice_prefix STRING,
  
  -- Timestamps for tracking
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  ingested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY DATE(created)
CLUSTER BY customer_id, email
OPTIONS(
  description="Processed Stripe customers data with flattened schema"
);

-- Subscriptions processed table
CREATE TABLE IF NOT EXISTS stripe_processed.subscriptions (
  subscription_id STRING NOT NULL,
  object_type STRING,
  status STRING,
  created TIMESTAMP,
  created_timestamp INT64,
  
  -- Period information
  current_period_start TIMESTAMP,
  current_period_end TIMESTAMP,
  cancel_at_period_end BOOLEAN,
  canceled_at TIMESTAMP,
  ended_at TIMESTAMP,
  
  -- Customer information
  customer_id STRING,
  
  -- Pricing information
  currency STRING,
  amount FLOAT64,
  subscription_interval STRING,
  interval_count INT64,
  
  -- Plan information
  plan_name STRING,
  plan_id STRING,
  product_id STRING,
  
  -- Collection method
  collection_method STRING,
  
  -- Timestamps for tracking
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  ingested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY DATE(created)
CLUSTER BY subscription_id, customer_id
OPTIONS(
  description="Processed Stripe subscriptions data with flattened schema"
);

