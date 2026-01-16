-- Create metadata tables for tracking sync state

-- Sync history table to track incremental loads
CREATE TABLE IF NOT EXISTS stripe_metadata.sync_history (
  entity_type STRING NOT NULL,           -- 'customers', 'subscriptions', 'invoices'
  last_sync_timestamp TIMESTAMP,         -- Last successful sync time (Stripe created field)
  last_synced_id STRING,                 -- Last synced Stripe object ID
  records_synced INT64,                  -- Number of records synced in last run
  sync_started_at TIMESTAMP,             -- When sync started
  sync_completed_at TIMESTAMP,           -- When sync completed
  status STRING,                         -- 'success', 'failed', 'in_progress'
  error_message STRING                   -- Error details if failed
)
PARTITION BY DATE(sync_completed_at)
OPTIONS(
  description="Tracks sync state for incremental Stripe data loads"
);

-- Initialize default rows for each entity type if they don't exist
MERGE stripe_metadata.sync_history AS target
USING (
  SELECT 'customers' AS entity_type
  UNION ALL
  SELECT 'subscriptions' AS entity_type
) AS source
ON target.entity_type = source.entity_type
WHEN NOT MATCHED THEN
  INSERT (
    entity_type,
    last_sync_timestamp,
    last_synced_id,
    records_synced,
    sync_started_at,
    sync_completed_at,
    status,
    error_message
  )
  VALUES (
    source.entity_type,
    TIMESTAMP('1970-01-01 00:00:00'),  -- Start from epoch for first full sync
    NULL,
    0,
    NULL,
    NULL,
    'pending',
    NULL
  );

