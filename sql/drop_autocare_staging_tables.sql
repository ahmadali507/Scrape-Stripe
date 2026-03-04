-- Drop legacy staging tables (no longer used after switch to stripe-customers + full refresh).
-- Safe to run multiple times. Run after create_autocare_processed_tables.sql when upgrading.

DROP TABLE IF EXISTS autocare_processed.staging_customers;
DROP TABLE IF EXISTS autocare_processed.staging_subscriptions;
DROP TABLE IF EXISTS autocare_processed.staging_sessions;
DROP TABLE IF EXISTS autocare_processed.staging_cars;
