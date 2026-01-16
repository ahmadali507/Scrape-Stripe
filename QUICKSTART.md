# Quick Start Guide - 5 Minutes to Production

This guide gets your Stripe to BigQuery pipeline running in 5 minutes.

## Prerequisites

- ✅ Google Cloud Project with billing enabled
- ✅ Stripe API key (sk_test_* or sk_live_*)
- ✅ Owner/Editor permissions on GCP project

## Step-by-Step Setup

### 1. Open Google Cloud Shell (30 seconds)

1. Go to https://console.cloud.google.com
2. Select your project from the dropdown
3. Click the Cloud Shell icon (📟) in the top right
4. Wait for shell to initialize

### 2. Upload Files (1 minute)

**Option A: Using Git**
```bash
git clone <your-repo-url>
cd Scrape-Stripe
```

**Option B: Using Cloud Shell Upload**
1. Click the three dots (⋮) in Cloud Shell
2. Select "Upload"
3. Upload the entire `Scrape-Stripe` folder
4. Navigate to the folder:
```bash
cd Scrape-Stripe
```

### 3. Make Scripts Executable (10 seconds)

```bash
chmod +x gcp-setup/*.sh
cd gcp-setup
```

### 4. Run One-Line Setup (2 minutes)

```bash
./setup.sh && ./setup-secrets.sh && ./create-tables.sh
```

**What this does:**
- Enables GCP APIs
- Creates service account
- Creates BigQuery datasets and tables
- Stores your Stripe API key securely

**You'll be prompted for**: Your Stripe Secret Key

### 5. Deploy Function & Scheduler (2 minutes)

```bash
./deploy-function.sh && ./setup-scheduler.sh
```

### 6. Test It! (30 seconds)

```bash
./test-pipeline.sh
```

## Done! 🎉

Your pipeline is now:
- ✅ Syncing Stripe data to BigQuery
- ✅ Running automatically every day at 6:00 AM UTC
- ✅ Storing data in organized tables

## What You Have Now

### BigQuery Datasets
- `stripe_raw` - Raw JSON from Stripe
- `stripe_processed` - Clean, queryable tables
- `stripe_metadata` - Sync tracking

### Tables Ready to Query
```sql
-- View your customers
SELECT * FROM `stripe_processed.customers` LIMIT 10;

-- View subscriptions
SELECT * FROM `stripe_processed.subscriptions` LIMIT 10;

-- Check sync status
SELECT * FROM `stripe_metadata.sync_history` 
ORDER BY sync_completed_at DESC;
```

## Quick Commands

### Trigger Manual Sync
```bash
gcloud scheduler jobs run stripe-bigquery-daily-sync --location=us-central1
```

### View Logs
```bash
gcloud functions logs read stripe-bigquery-sync --region=us-central1 --gen2 --limit=20
```

### Query Data
```bash
bq query --use_legacy_sql=false \
  'SELECT COUNT(*) as total_customers FROM `stripe_processed.customers`'
```

### Check Scheduler Status
```bash
gcloud scheduler jobs describe stripe-bigquery-daily-sync --location=us-central1
```

## Next Steps

1. **Connect to Data Studio**: Build dashboards from your BigQuery tables
2. **Set Up Alerts**: Get notified if sync fails
3. **Explore Data**: Run analytics on your Stripe data
4. **Customize**: Modify sync schedule or add more data types

## Need Help?

- 📖 Full guide: See `DEPLOYMENT_GUIDE.md`
- 🔍 Logs: Check Cloud Function logs for detailed error messages
- 📊 Data: Query `stripe_metadata.sync_history` for sync status
- 🧪 Test: Run `./test-pipeline.sh` to verify everything

## Troubleshooting

### "Permission denied" errors
```bash
chmod +x gcp-setup/*.sh
```

### "Project not set" error
```bash
gcloud config set project YOUR_PROJECT_ID
```

### "API not enabled" error
Just wait 1-2 minutes - APIs take time to enable, then re-run the script.

### No data appearing
1. Check if you have data in Stripe
2. Verify API key: `gcloud secrets versions access latest --secret=stripe-api-key`
3. Check logs: `gcloud functions logs read stripe-bigquery-sync --region=us-central1 --gen2`

## Cost

**Typical monthly cost**: < $1

The pipeline uses:
- Cloud Functions (free tier: 2M invocations)
- Cloud Scheduler (free tier: 3 jobs)
- BigQuery (free tier: 10GB storage, 1TB queries)
- Secret Manager (free tier: 6 secrets)

For most businesses, this stays within free tier limits.

## Architecture

```
┌─────────────────┐
│ Cloud Scheduler │ Triggers daily at 6 AM UTC
│   (Free Tier)   │
└────────┬────────┘
         │
         v
┌─────────────────┐
│ Cloud Function  │ Fetches new data from Stripe
│  (Serverless)   │ Stores in BigQuery
└────────┬────────┘
         │
         v
┌─────────────────┐
│   BigQuery      │ Three datasets:
│  (Data Warehouse)│ - Raw (JSON backup)
│                 │ - Processed (clean tables)
│                 │ - Metadata (sync tracking)
└─────────────────┘
```

Your data is:
- 🔒 Secure (API keys in Secret Manager)
- 🔄 Automatically synced daily
- 📈 Ready for analytics
- 💰 Cost-efficient (< $1/month)

