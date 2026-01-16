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

-- Invoices processed table
CREATE TABLE IF NOT EXISTS stripe_processed.invoices (
  invoice_id STRING NOT NULL,
  object_type STRING,
  number STRING,
  status STRING,
  created TIMESTAMP,
  created_timestamp INT64,
  
  -- Customer information
  customer_id STRING,
  customer_email STRING,
  customer_name STRING,
  
  -- Subscription information
  subscription_id STRING,
  
  -- Amount information
  currency STRING,
  amount_due INT64,
  amount_paid INT64,
  amount_remaining INT64,
  subtotal INT64,
  total INT64,
  tax INT64,
  
  -- Dates
  due_date TIMESTAMP,
  paid_at TIMESTAMP,
  period_start TIMESTAMP,
  period_end TIMESTAMP,
  
  -- Payment information
  paid BOOLEAN,
  attempted BOOLEAN,
  attempt_count INT64,
  
  -- Invoice details
  description STRING,
  statement_descriptor STRING,
  
  -- Timestamps for tracking
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  ingested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY DATE(created)
CLUSTER BY invoice_id, customer_id
OPTIONS(
  description="Processed Stripe invoices data with flattened schema"
);

