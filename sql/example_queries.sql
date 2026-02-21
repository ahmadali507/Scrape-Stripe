-- Example BigQuery Queries for Stripe Data Analysis
-- Copy these into BigQuery Console or use with bq command line tool

-- ============================================================
-- SYNC MONITORING
-- ============================================================

-- 1. Check latest sync status for all entity types
SELECT 
  entity_type,
  last_sync_timestamp,
  records_synced,
  sync_completed_at,
  status,
  error_message
FROM `stripe_metadata.sync_history`
WHERE sync_completed_at = (
  SELECT MAX(sync_completed_at) 
  FROM `stripe_metadata.sync_history` AS t2 
  WHERE t2.entity_type = stripe_metadata.sync_history.entity_type
)
ORDER BY entity_type;

-- 2. Sync history for last 7 days
SELECT 
  entity_type,
  DATE(sync_completed_at) as sync_date,
  SUM(records_synced) as total_records,
  COUNT(*) as sync_count,
  COUNTIF(status = 'success') as successful_syncs,
  COUNTIF(status = 'failed') as failed_syncs
FROM `stripe_metadata.sync_history`
WHERE sync_completed_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY entity_type, sync_date
ORDER BY sync_date DESC, entity_type;

-- 3. Failed syncs with errors
SELECT 
  entity_type,
  sync_started_at,
  sync_completed_at,
  records_synced,
  error_message
FROM `stripe_metadata.sync_history`
WHERE status = 'failed'
ORDER BY sync_completed_at DESC
LIMIT 20;


-- ============================================================
-- CUSTOMER ANALYTICS
-- ============================================================

-- 4. Customer growth over time
SELECT 
  DATE_TRUNC(created, MONTH) as month,
  COUNT(*) as new_customers,
  SUM(COUNT(*)) OVER (ORDER BY DATE_TRUNC(created, MONTH)) as cumulative_customers
FROM `stripe_processed.customers`
GROUP BY month
ORDER BY month DESC;

-- 5. Customers by country
SELECT 
  address_country as country,
  COUNT(*) as customer_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as percentage
FROM `stripe_processed.customers`
WHERE address_country IS NOT NULL
GROUP BY country
ORDER BY customer_count DESC
LIMIT 20;

-- 6. Customers with delinquent status
SELECT 
  customer_id,
  email,
  name,
  balance / 100 as balance_usd,
  created
FROM `stripe_processed.customers`
WHERE delinquent = true
ORDER BY balance DESC;

-- 7. Recent customers (last 30 days)
SELECT 
  customer_id,
  email,
  name,
  address_country,
  created
FROM `stripe_processed.customers`
WHERE created >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
ORDER BY created DESC;


-- ============================================================
-- SUBSCRIPTION ANALYTICS
-- ============================================================

-- 8. Active subscriptions summary
SELECT 
  status,
  COUNT(*) as subscription_count,
  SUM(amount) as total_mrr,
  AVG(amount) as avg_subscription_value,
  currency
FROM `stripe_processed.subscriptions`
GROUP BY status, currency
ORDER BY subscription_count DESC;

-- 9. MRR (Monthly Recurring Revenue) by plan
SELECT 
  plan_name,
  subscription_interval,
  COUNT(*) as subscription_count,
  SUM(amount) as total_value,
  currency
FROM `stripe_processed.subscriptions`
WHERE status = 'active'
GROUP BY plan_name, subscription_interval, currency
ORDER BY total_value DESC;

-- 10. Subscription churn analysis
SELECT 
  DATE_TRUNC(canceled_at, MONTH) as month,
  COUNT(*) as canceled_subscriptions,
  SUM(amount) as churned_mrr,
  AVG(TIMESTAMP_DIFF(canceled_at, created, DAY)) as avg_lifetime_days
FROM `stripe_processed.subscriptions`
WHERE canceled_at IS NOT NULL
GROUP BY month
ORDER BY month DESC
LIMIT 12;

-- 11. Subscriptions ending soon (next 7 days)
SELECT 
  subscription_id,
  customer_id,
  status,
  amount,
  currency,
  current_period_end,
  cancel_at_period_end
FROM `stripe_processed.subscriptions`
WHERE current_period_end BETWEEN CURRENT_TIMESTAMP() 
  AND TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
ORDER BY current_period_end;

-- 12. Customer lifetime value (based on active subscriptions)
SELECT 
  c.customer_id,
  c.email,
  c.name,
  COUNT(s.subscription_id) as active_subscriptions,
  SUM(s.amount) as total_monthly_value,
  c.currency
FROM `stripe_processed.customers` c
JOIN `stripe_processed.subscriptions` s ON c.customer_id = s.customer_id
WHERE s.status = 'active'
GROUP BY c.customer_id, c.email, c.name, c.currency
ORDER BY total_monthly_value DESC
LIMIT 50;


-- ============================================================
-- INVOICE ANALYTICS
-- ============================================================

-- 13. Revenue by month
SELECT 
  DATE_TRUNC(created, MONTH) as month,
  COUNT(*) as invoice_count,
  SUM(amount_paid) / 100 as total_revenue,
  SUM(amount_due - amount_paid) / 100 as outstanding,
  currency
FROM `stripe_processed.invoices`
GROUP BY month, currency
ORDER BY month DESC
LIMIT 12;

-- 14. Invoice payment status
SELECT 
  status,
  paid,
  COUNT(*) as invoice_count,
  SUM(total) / 100 as total_amount,
  SUM(amount_paid) / 100 as paid_amount,
  SUM(amount_remaining) / 100 as remaining_amount,
  currency
FROM `stripe_processed.invoices`
GROUP BY status, paid, currency
ORDER BY invoice_count DESC;

-- 15. Overdue invoices
SELECT 
  invoice_id,
  number,
  customer_id,
  customer_email,
  due_date,
  amount_remaining / 100 as amount_due,
  currency,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), due_date, DAY) as days_overdue
FROM `stripe_processed.invoices`
WHERE status != 'paid'
  AND due_date < CURRENT_TIMESTAMP()
  AND amount_remaining > 0
ORDER BY days_overdue DESC;

-- 16. Failed payment attempts
SELECT 
  DATE_TRUNC(created, DAY) as date,
  COUNT(*) as failed_attempts,
  SUM(amount_due) / 100 as total_attempted,
  currency
FROM `stripe_processed.invoices`
WHERE attempted = true 
  AND paid = false
GROUP BY date, currency
ORDER BY date DESC
LIMIT 30;


-- ============================================================
-- COMBINED ANALYSIS
-- ============================================================

-- 17. Customer 360 view (customers with their subscriptions and invoices)
SELECT 
  c.customer_id,
  c.email,
  c.name,
  c.address_country,
  c.created as customer_since,
  COUNT(DISTINCT s.subscription_id) as total_subscriptions,
  COUNT(DISTINCT CASE WHEN s.status = 'active' THEN s.subscription_id END) as active_subscriptions,
  SUM(CASE WHEN s.status = 'active' THEN s.amount ELSE 0 END) as monthly_value,
  COUNT(DISTINCT i.invoice_id) as total_invoices,
  SUM(i.amount_paid) / 100 as lifetime_revenue,
  SUM(i.amount_remaining) / 100 as outstanding_balance
FROM `stripe_processed.customers` c
LEFT JOIN `stripe_processed.subscriptions` s ON c.customer_id = s.customer_id
LEFT JOIN `stripe_processed.invoices` i ON c.customer_id = i.customer_id
GROUP BY c.customer_id, c.email, c.name, c.address_country, c.created
ORDER BY lifetime_revenue DESC
LIMIT 100;

-- 18. Revenue cohort analysis
WITH customer_cohorts AS (
  SELECT 
    customer_id,
    DATE_TRUNC(created, MONTH) as cohort_month
  FROM `stripe_processed.customers`
)
SELECT 
  cc.cohort_month,
  DATE_TRUNC(i.created, MONTH) as revenue_month,
  TIMESTAMP_DIFF(DATE_TRUNC(i.created, MONTH), cc.cohort_month, MONTH) as months_since_signup,
  COUNT(DISTINCT i.customer_id) as paying_customers,
  SUM(i.amount_paid) / 100 as revenue
FROM customer_cohorts cc
JOIN `stripe_processed.invoices` i ON cc.customer_id = i.customer_id
WHERE i.paid = true
GROUP BY cohort_month, revenue_month, months_since_signup
ORDER BY cohort_month DESC, months_since_signup;

-- 19. Subscription renewal rate
WITH subscription_periods AS (
  SELECT 
    subscription_id,
    customer_id,
    status,
    current_period_start,
    current_period_end,
    cancel_at_period_end,
    CASE 
      WHEN status = 'active' AND cancel_at_period_end = false THEN 'will_renew'
      WHEN status = 'active' AND cancel_at_period_end = true THEN 'will_cancel'
      WHEN status = 'canceled' THEN 'canceled'
      ELSE 'other'
    END as renewal_status
  FROM `stripe_processed.subscriptions`
)
SELECT 
  renewal_status,
  COUNT(*) as subscription_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as percentage
FROM subscription_periods
GROUP BY renewal_status
ORDER BY subscription_count DESC;

-- 20. Top customers by revenue (last 12 months)
SELECT 
  c.customer_id,
  c.email,
  c.name,
  c.address_country,
  COUNT(DISTINCT i.invoice_id) as invoice_count,
  SUM(i.amount_paid) / 100 as total_revenue_12mo,
  AVG(i.amount_paid) / 100 as avg_invoice_value,
  i.currency
FROM `stripe_processed.customers` c
JOIN `stripe_processed.invoices` i ON c.customer_id = i.customer_id
WHERE i.created >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 12 MONTH)
  AND i.paid = true
GROUP BY c.customer_id, c.email, c.name, c.address_country, i.currency
ORDER BY total_revenue_12mo DESC
LIMIT 50;


-- ============================================================
-- DATA QUALITY CHECKS
-- ============================================================

-- 21. Check for duplicate records in processed tables
SELECT 
  'customers' as table_name,
  COUNT(*) as total_rows,
  COUNT(DISTINCT customer_id) as unique_ids,
  COUNT(*) - COUNT(DISTINCT customer_id) as duplicates
FROM `stripe_processed.customers`
UNION ALL
SELECT 
  'subscriptions',
  COUNT(*),
  COUNT(DISTINCT subscription_id),
  COUNT(*) - COUNT(DISTINCT subscription_id)
FROM `stripe_processed.subscriptions`
UNION ALL
SELECT 
  'invoices',
  COUNT(*),
  COUNT(DISTINCT invoice_id),
  COUNT(*) - COUNT(DISTINCT invoice_id)
FROM `stripe_processed.invoices`;

-- 22. Data freshness check
SELECT 
  'customers' as table_name,
  MAX(ingested_at) as last_ingested,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(ingested_at), HOUR) as hours_since_last_update
FROM `stripe_processed.customers`
UNION ALL
SELECT 
  'subscriptions',
  MAX(ingested_at),
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(ingested_at), HOUR)
FROM `stripe_processed.subscriptions`
UNION ALL
SELECT 
  'invoices',
  MAX(ingested_at),
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(ingested_at), HOUR)
FROM `stripe_processed.invoices`;

-- 23. Record count comparison (raw vs processed)
SELECT 
  'customers' as entity,
  (SELECT COUNT(*) FROM `stripe_raw.customers_raw`) as raw_count,
  (SELECT COUNT(*) FROM `stripe_processed.customers`) as processed_count,
  (SELECT COUNT(*) FROM `stripe_processed.customers`) - 
  (SELECT COUNT(*) FROM `stripe_raw.customers_raw`) as difference
UNION ALL
SELECT 
  'subscriptions',
  (SELECT COUNT(*) FROM `stripe_raw.subscriptions_raw`),
  (SELECT COUNT(*) FROM `stripe_processed.subscriptions`),
  (SELECT COUNT(*) FROM `stripe_processed.subscriptions`) - 
  (SELECT COUNT(*) FROM `stripe_raw.subscriptions_raw`)
UNION ALL
SELECT 
  'invoices',
  (SELECT COUNT(*) FROM `stripe_raw.invoices_raw`),
  (SELECT COUNT(*) FROM `stripe_processed.invoices`),
  (SELECT COUNT(*) FROM `stripe_processed.invoices`) - 
  (SELECT COUNT(*) FROM `stripe_raw.invoices_raw`);


-- ============================================================
-- UNIFIED CUSTOMERS (Stripe + AutoCare: one row per customer,
-- with cars, sessions, subscriptions and tiers as arrays)
-- ============================================================
-- Requires: create_unified_customer_view.sql applied; autocare_* tables populated.

-- 1. One row per customer with all fields (no duplication)
SELECT
  customer_id,
  email,
  name,
  phone,
  stripe_email,
  stripe_name,
  autocare_client_id,
  autocare_email,
  autocare_first_name,
  autocare_last_name,
  ARRAY_LENGTH(cars) AS car_count,
  ARRAY_LENGTH(sessions) AS session_count,
  ARRAY_LENGTH(autocare_subscriptions_with_tiers) AS autocare_sub_count,
  ARRAY_LENGTH(stripe_subscriptions) AS stripe_sub_count
FROM `stripe_processed.unified_customers`
LIMIT 20;

-- 2. Unnest cars for customers that have cars
SELECT
  u.customer_id,
  u.email,
  u.name,
  car.car_id,
  car.make,
  car.model,
  car.year,
  car.license_plate,
  car.vin,
  car.car_json_data
FROM `stripe_processed.unified_customers` u,
  UNNEST(u.cars) AS car
WHERE ARRAY_LENGTH(u.cars) > 0;

-- 3. Unnest sessions for customers that have sessions
SELECT
  u.customer_id,
  u.email,
  s.session_id,
  s.session_date,
  s.session_type,
  s.session_description,
  s.location_name
FROM `stripe_processed.unified_customers` u,
  UNNEST(u.sessions) AS s
WHERE ARRAY_LENGTH(u.sessions) > 0;

-- 4. Unnest AutoCare subscriptions with tier info
SELECT
  u.customer_id,
  u.email,
  sub.subscription_id,
  sub.sub_status,
  sub.tier_name,
  sub.tier_product_key,
  sub.tier_perks,
  sub.tier_refund_required,
  sub.sub_car_ids
FROM `stripe_processed.unified_customers` u,
  UNNEST(u.autocare_subscriptions_with_tiers) AS sub
WHERE ARRAY_LENGTH(u.autocare_subscriptions_with_tiers) > 0;

