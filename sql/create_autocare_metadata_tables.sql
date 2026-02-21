-- AutoCare sync metadata (same pattern as Stripe)

CREATE TABLE IF NOT EXISTS autocare_metadata.sync_history (
  entity_type STRING NOT NULL,          -- 'autocare_tiers', 'autocare_marketing_data'
  last_sync_timestamp TIMESTAMP,
  last_synced_id STRING,
  records_synced INT64,
  sync_started_at TIMESTAMP,
  sync_completed_at TIMESTAMP,
  status STRING,
  error_message STRING
)
PARTITION BY DATE(sync_completed_at)
OPTIONS(
  description="Tracks sync state for AutoCare API loads (full refresh per run)"
);
