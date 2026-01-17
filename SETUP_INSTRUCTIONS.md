# Fresh Setup Instructions - Customers & Subscriptions Only

## What Changed

The pipeline has been updated to sync **only customers and subscriptions** (invoices removed due to API restrictions).

## Step-by-Step Setup


### Step 2: Recreate BigQuery Structure

```bash
# Create datasets
./setup.sh
```

**What this does:**
- Creates `stripe_raw`, `stripe_processed`, `stripe_metadata` datasets
- No need to re-enable APIs (already done)
- Reuses existing service account

---

### Step 3: Create Tables

```bash
# Create new tables (without invoices)
./create-tables.sh
```

**Tables created:**
- `stripe_metadata.sync_history`
- `stripe_raw.customers_raw`
- `stripe_raw.subscriptions_raw`
- `stripe_processed.customers`
- `stripe_processed.subscriptions`

---

### Step 4: Deploy Updated Cloud Function

```bash
# Deploy with 2GB memory and no invoice code
./deploy-function.sh
```

**Takes:** 2-5 minutes

**New features:**
- 2GB memory (prevents crashes)
- Batch processing (500 records at a time)
- Only syncs customers and subscriptions

---

### Step 5: Set Up Scheduler

```bash
# Create daily sync job (6:00 AM UTC)
./setup-scheduler.sh
```

---

### Step 6: Test the Pipeline

```bash
# Run comprehensive tests
./test-pipeline.sh
```

**Or trigger manually:**

```bash
# Trigger sync
gcloud scheduler jobs run stripe-bigquery-daily-sync --location=us-central1

# Watch logs
gcloud functions logs read stripe-bigquery-sync \
  --region=us-central1 \
  --gen2 \
  --limit=100 \
  --format="table(time_utc, severity, textPayload)"
```

---

## Verify Success

### Check Sync Status

```bash
bq query --use_legacy_sql=false \
  'SELECT * FROM `stripe_metadata.sync_history` 
   ORDER BY sync_completed_at DESC LIMIT 5'
```

### View Data

```bash
# Count records
bq query --use_legacy_sql=false '
SELECT 
  (SELECT COUNT(*) FROM `stripe_processed.customers`) as customers,
  (SELECT COUNT(*) FROM `stripe_processed.subscriptions`) as subscriptions
'

# View customers
bq query --use_legacy_sql=false \
  'SELECT customer_id, email, name, created 
   FROM `stripe_processed.customers` LIMIT 10'

# View subscriptions
bq query --use_legacy_sql=false \
  'SELECT subscription_id, customer_id, status, amount, currency 
   FROM `stripe_processed.subscriptions` LIMIT 10'
```

---

## What's Synced Now

### ✅ Customers
- Basic info: ID, email, name, phone, description
- Address: line1, line2, city, state, postal_code, country
- Billing: currency, balance, delinquent status
- Metadata: default_source, invoice_prefix
- Timestamps: created, updated_at, ingested_at

### ✅ Subscriptions
- Basic info: ID, customer, object_type, status
- Periods: current_period_start, current_period_end
- Cancellation: cancel_at_period_end, canceled_at, ended_at
- Pricing: amount, currency, subscription_interval, interval_count
- Plan: plan_name, plan_id, product_id
- Collection: collection_method
- Timestamps: created, updated_at, ingested_at

### ❌ Invoices
- Removed due to Stripe API key restrictions
- Can be added later if you get full API access

---

## Troubleshooting

### "Table not found" errors?
Run `./create-tables.sh` again

### Function still failing?
```bash
# Check logs
gcloud functions logs read stripe-bigquery-sync \
  --region=us-central1 \
  --gen2 \
  --limit=50 | grep -i error

# Check memory allocation
gcloud functions describe stripe-bigquery-sync \
  --region=us-central1 \
  --gen2 \
  --format="value(serviceConfig.availableMemory)"
# Should show: 2G
```

### Stripe API errors?
Make sure your API key has permissions for:
- ✅ Customers - Read
- ✅ Subscriptions - Read

---

## One-Line Complete Setup

After running cleanup, you can run everything in one command:

```bash
cd ~/Scrape-Stripe/gcp-setup
./cleanup.sh && \
./setup.sh && \
./create-tables.sh && \
./deploy-function.sh && \
./setup-scheduler.sh && \
./test-pipeline.sh
```

(You'll need to type 'yes' for cleanup confirmation)

---

## Cost

**Monthly cost:** < $1

- Cloud Functions (2GB): ~$0.50/month (1 daily invocation)
- Cloud Scheduler: Free (first 3 jobs)
- BigQuery Storage: Free (within 10GB tier)
- BigQuery Queries: Free (within 1TB tier)
- Secret Manager: Free (first 6 secrets)

---

## Next Steps

1. ✅ **Run the setup** (6 steps above)
2. 📊 **Connect to Data Studio** for dashboards
3. 🔔 **Set up alerts** for failed syncs
4. 📈 **Run analytics** on your Stripe data

---

## Summary

You now have a **clean, working pipeline** that syncs:
- ✅ Customers
- ✅ Subscriptions
- ✅ Daily at 6:00 AM UTC
- ✅ With 2GB memory (no crashes)
- ✅ Batch processing (efficient)
- ✅ Incremental loading (fast)

No more invoice errors! 🎉

