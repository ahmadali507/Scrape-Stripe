# Stripe to BigQuery Pipeline - Deployment Guide

This guide will walk you through deploying the complete Stripe to BigQuery data pipeline on Google Cloud Platform.

## Overview

The pipeline automatically syncs Stripe data (customers, subscriptions, invoices) to BigQuery daily at 6:00 AM UTC using:

- **Cloud Functions**: Serverless ETL pipeline
- **Cloud Scheduler**: Daily automated triggers
- **BigQuery**: Data warehouse with raw and processed tables
- **Secret Manager**: Secure API key storage

## Architecture

```
Cloud Scheduler (6 AM UTC) 
    → Cloud Function (ETL Pipeline)
        → Secret Manager (API Key)
        → Stripe API (Incremental Fetch)
        → BigQuery Raw Tables (JSON Storage)
        → BigQuery Processed Tables (Flattened Data)
        → BigQuery Metadata (Sync Tracking)
```

## Prerequisites

1. **Google Cloud Project**: An existing GCP project with billing enabled
2. **Stripe Account**: Access to Stripe API keys
3. **Google Cloud Shell**: All scripts are designed to run in Cloud Shell
4. **Required Permissions**: Owner or Editor role on the GCP project

## Deployment Steps

### Step 1: Open Google Cloud Shell

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Select your project
3. Click the Cloud Shell icon (top right)
4. Wait for the shell to initialize

### Step 2: Upload and Prepare Files

```bash
# Clone or upload your repository to Cloud Shell
# If you have this in a git repository:
git clone <your-repo-url>
cd Scrape-Stripe

# Or use the Cloud Shell upload feature to upload the Scrape-Stripe folder

# Make scripts executable
chmod +x gcp-setup/*.sh
```

### Step 3: Run Initial Setup

This script will:
- Enable required GCP APIs
- Create service account
- Create BigQuery datasets

```bash
cd gcp-setup
./setup.sh
```

**Expected Output**: Confirmation of APIs enabled, service account created, and datasets created.

### Step 4: Store Stripe API Key

This script will securely store your Stripe API key in Secret Manager:

```bash
./setup-secrets.sh
```

**When Prompted**: Enter your Stripe Secret Key (starts with `sk_test_` or `sk_live_`)

**Expected Output**: Confirmation that secret is stored and service account has access.

### Step 5: Create BigQuery Tables

This script will create all necessary tables:

```bash
./create-tables.sh
```

**Expected Output**: Confirmation of metadata, raw, and processed tables created.

**Tables Created**:
- `stripe_metadata.sync_history`
- `stripe_raw.customers_raw`
- `stripe_raw.subscriptions_raw`
- `stripe_raw.invoices_raw`
- `stripe_processed.customers`
- `stripe_processed.subscriptions`
- `stripe_processed.invoices`

### Step 6: Deploy Cloud Function

This script will deploy the ETL Cloud Function:

```bash
./deploy-function.sh
```

**Expected Duration**: 2-5 minutes

**Expected Output**: Function URL and deployment confirmation.

### Step 7: Set Up Cloud Scheduler

This script will create the daily scheduler job:

```bash
./setup-scheduler.sh
```

**Expected Output**: Scheduler job created with cron schedule `0 6 * * *` (6:00 AM UTC).

### Step 8: Test the Pipeline

This script will run comprehensive tests:

```bash
./test-pipeline.sh
```

**Expected Output**: Verification of all components and a test sync execution.

## Verification

### Check BigQuery Data

```bash
# View sync history
bq query --use_legacy_sql=false \
  'SELECT * FROM `stripe_metadata.sync_history` ORDER BY sync_completed_at DESC LIMIT 5'

# View processed customers
bq query --use_legacy_sql=false \
  'SELECT customer_id, email, name, created FROM `stripe_processed.customers` LIMIT 10'

# View processed subscriptions
bq query --use_legacy_sql=false \
  'SELECT subscription_id, customer_id, status, amount, currency FROM `stripe_processed.subscriptions` LIMIT 10'
```

### View Cloud Function Logs

```bash
gcloud functions logs read stripe-bigquery-sync \
  --region=us-central1 \
  --gen2 \
  --limit=50
```

### Check Scheduler Status

```bash
gcloud scheduler jobs describe stripe-bigquery-daily-sync \
  --location=us-central1
```

## Manual Operations

### Trigger Manual Sync

```bash
# Via gcloud
gcloud scheduler jobs run stripe-bigquery-daily-sync --location=us-central1

# Via HTTP
curl -X POST <FUNCTION_URL>
```

### Sync Specific Entity Type

```bash
curl -X POST <FUNCTION_URL> \
  -H "Content-Type: application/json" \
  -d '{"entities": ["customers"]}'
```

### Pause Scheduled Sync

```bash
gcloud scheduler jobs pause stripe-bigquery-daily-sync --location=us-central1
```

### Resume Scheduled Sync

```bash
gcloud scheduler jobs resume stripe-bigquery-daily-sync --location=us-central1
```

### Update Scheduler Time

```bash
# Change to 8:00 AM UTC
gcloud scheduler jobs update http stripe-bigquery-daily-sync \
  --location=us-central1 \
  --schedule="0 8 * * *"
```

## Monitoring

### Cloud Function Metrics

View in Cloud Console:
1. Go to Cloud Functions
2. Click `stripe-bigquery-sync`
3. View Metrics tab for:
   - Invocations
   - Execution time
   - Memory usage
   - Errors

### BigQuery Usage

```bash
# Check table sizes
bq ls --format=prettyjson stripe_raw
bq ls --format=prettyjson stripe_processed

# View row counts
bq query --use_legacy_sql=false '
SELECT 
  "customers_raw" as table_name,
  COUNT(*) as row_count 
FROM `stripe_raw.customers_raw`
UNION ALL
SELECT 
  "subscriptions_raw",
  COUNT(*) 
FROM `stripe_raw.subscriptions_raw`
UNION ALL
SELECT 
  "invoices_raw",
  COUNT(*) 
FROM `stripe_raw.invoices_raw`
'
```

### Sync History Analysis

```bash
bq query --use_legacy_sql=false '
SELECT 
  entity_type,
  last_sync_timestamp,
  records_synced,
  sync_completed_at,
  status,
  error_message
FROM `stripe_metadata.sync_history`
WHERE DATE(sync_completed_at) >= CURRENT_DATE() - 7
ORDER BY sync_completed_at DESC
'
```

## Troubleshooting

### Function Fails with Authentication Error

**Problem**: Cannot access Secret Manager

**Solution**:
```bash
# Verify service account has access
gcloud secrets add-iam-policy-binding stripe-api-key \
  --member="serviceAccount:stripe-sync-sa@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

### No Data Syncing

**Problem**: Empty results from Stripe

**Check**:
1. Verify Stripe API key is correct: `gcloud secrets versions access latest --secret=stripe-api-key`
2. Check if you have data in Stripe account
3. Review function logs for errors

### BigQuery Permission Errors

**Problem**: Cannot write to BigQuery

**Solution**:
```bash
PROJECT_ID=$(gcloud config get-value project)
SERVICE_ACCOUNT="stripe-sync-sa@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/bigquery.dataEditor"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/bigquery.jobUser"
```

### Function Timeout

**Problem**: Function times out for large datasets

**Solution**: Increase timeout
```bash
gcloud functions deploy stripe-bigquery-sync \
  --gen2 \
  --timeout=540s \
  --region=us-central1
```

## Cost Estimation

### Monthly Costs (Typical Small Business)

- **Cloud Functions**: ~$0.40/month (1 invocation/day)
- **Cloud Scheduler**: Free (first 3 jobs)
- **BigQuery Storage**: ~$0.20/month (10GB)
- **BigQuery Queries**: Free (within 1TB/month limit)
- **Secret Manager**: Free (first 6 secrets)

**Total Estimated**: < $1/month for most use cases

### Cost Optimization

1. **Incremental Loading**: Only fetch new/updated records (already implemented)
2. **Partitioned Tables**: Tables are partitioned by date for efficient queries
3. **Clustered Tables**: Tables are clustered on key columns
4. **Retention Policy**: Consider adding retention on raw tables:

```sql
ALTER TABLE stripe_raw.customers_raw
SET OPTIONS (
  partition_expiration_days=365
);
```

## Data Schema

### Customers Table
- `customer_id`, `email`, `name`, `phone`
- `address_*` fields (line1, city, state, postal_code, country)
- `currency`, `balance`, `delinquent`
- `created`, `updated_at`, `ingested_at`

### Subscriptions Table
- `subscription_id`, `customer_id`, `status`
- `current_period_start`, `current_period_end`
- `amount`, `currency`, `interval`
- `plan_name`, `plan_id`, `product_id`
- `created`, `updated_at`, `ingested_at`

### Invoices Table
- `invoice_id`, `customer_id`, `subscription_id`
- `number`, `status`, `paid`, `attempted`
- `amount_due`, `amount_paid`, `amount_remaining`
- `total`, `subtotal`, `tax`
- `created`, `due_date`, `paid_at`

## Security Best Practices

✅ **Implemented**:
- API keys stored in Secret Manager (never in code)
- Service account with least-privilege permissions
- Cloud Function requires authentication
- Audit logging enabled

🔒 **Additional Recommendations**:
1. Enable VPC Service Controls for BigQuery
2. Set up data access audit logs
3. Implement BigQuery column-level security if needed
4. Rotate Stripe API keys periodically

## Next Steps

1. **Set Up Alerts**: Configure Cloud Monitoring alerts for function failures
2. **Create Dashboards**: Build BigQuery/Data Studio dashboards
3. **Optimize Queries**: Create views for common query patterns
4. **Add More Entities**: Extend to sync charges, refunds, etc.
5. **Implement CDC**: Add change data capture for updates

## Support

For issues or questions:
1. Check Cloud Function logs
2. Review sync_history table for error messages
3. Verify all setup steps completed successfully
4. Check GCP quotas and limits

## Cleanup (If Needed)

To remove all resources:

```bash
# Delete scheduler
gcloud scheduler jobs delete stripe-bigquery-daily-sync --location=us-central1

# Delete function
gcloud functions delete stripe-bigquery-sync --region=us-central1 --gen2

# Delete BigQuery datasets
bq rm -r -f stripe_raw
bq rm -r -f stripe_processed
bq rm -r -f stripe_metadata

# Delete secret
gcloud secrets delete stripe-api-key

# Delete service account
gcloud iam service-accounts delete stripe-sync-sa@PROJECT_ID.iam.gserviceaccount.com
```

