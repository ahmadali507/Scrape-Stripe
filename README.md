# Stripe to BigQuery Data Pipeline

Automated daily sync of Stripe data (customers, subscriptions, invoices) to Google BigQuery with incremental loading and complete audit trail.

## 🚀 Features

- ✅ **Automated Daily Sync** - Runs every morning at 6:00 AM UTC via Cloud Scheduler
- ✅ **Incremental Loading** - Only fetches new/updated records since last sync
- ✅ **Complete Audit Trail** - Stores raw JSON and processed data
- ✅ **Cost Efficient** - < $1/month for typical usage, leverages GCP free tier
- ✅ **Secure** - API keys stored in Secret Manager, never in code
- ✅ **Serverless** - No servers to manage, fully cloud-native
- ✅ **Scalable** - Handles datasets from small startups to large enterprises
- ✅ **Query Ready** - Clean, flattened tables ready for analytics

## 📊 What Gets Synced

| Stripe Entity | BigQuery Table | Fields |
|--------------|----------------|---------|
| **Customers** | `stripe_processed.customers` | ID, email, name, address, phone, created date, billing info |
| **Subscriptions** | `stripe_processed.subscriptions` | ID, customer, status, amount, plan, interval, period dates, cancellation info |

## 🏗️ Architecture

```
┌──────────────────┐
│ Cloud Scheduler  │  Triggers daily at 6 AM UTC
│   (Cron: 0 6 * *)│
└────────┬─────────┘
         │
         ▼
┌──────────────────┐         ┌─────────────────┐
│  Cloud Function  │────────▶│ Secret Manager  │
│  (ETL Pipeline)  │         │  (Stripe Key)   │
└────────┬─────────┘         └─────────────────┘
         │
         ├──────────▶ Fetch incremental data from Stripe API
         │
         ▼
┌──────────────────────────────────────────────┐
│              BigQuery                         │
│                                               │
│  ┌─────────────────────────────────────────┐ │
│  │ stripe_raw (Raw JSON Backup)            │ │
│  │  • customers_raw                        │ │
│  │  • subscriptions_raw                    │ │
│  └─────────────────────────────────────────┘ │
│                                               │
│  ┌─────────────────────────────────────────┐ │
│  │ stripe_processed (Clean Tables)         │ │
│  │  • customers                            │ │
│  │  • subscriptions                        │ │
│  └─────────────────────────────────────────┘ │
│                                               │
│  ┌─────────────────────────────────────────┐ │
│  │ stripe_metadata (Sync Tracking)         │ │
│  │  • sync_history                         │ │
│  └─────────────────────────────────────────┘ │
└──────────────────────────────────────────────┘
```

## 🎯 Quick Start

**Time Required**: 5 minutes

```bash
# 1. Open Google Cloud Shell
# 2. Upload/clone this repository
# 3. Run setup

cd Scrape-Stripe/gcp-setup
chmod +x *.sh

# One-line setup
./setup.sh && ./setup-secrets.sh && ./create-tables.sh && ./deploy-function.sh && ./setup-scheduler.sh

# Test it
./test-pipeline.sh
```

**That's it!** Your pipeline is now syncing data daily.

📖 **Full Guide**: See [QUICKSTART.md](QUICKSTART.md) for detailed steps  
📚 **Complete Documentation**: See [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)

## 📁 Project Structure

```
Scrape-Stripe/
├── cloud-function/           # Cloud Function source code
│   ├── main.py              # Entry point (HTTP trigger)
│   ├── stripe_client.py     # Stripe API client
│   ├── bigquery_client.py   # BigQuery operations
│   ├── requirements.txt     # Python dependencies
│   └── .gcloudignore        # Deployment exclusions
│
├── gcp-setup/               # Setup scripts for Cloud Shell
│   ├── setup.sh             # Main GCP setup (APIs, service account, datasets)
│   ├── setup-secrets.sh     # Store Stripe key in Secret Manager
│   ├── create-tables.sh     # Create BigQuery tables
│   ├── deploy-function.sh   # Deploy Cloud Function
│   ├── setup-scheduler.sh   # Configure Cloud Scheduler
│   └── test-pipeline.sh     # Test entire pipeline
│
├── sql/                     # BigQuery table definitions
│   ├── create_metadata_tables.sql
│   ├── create_raw_tables.sql
│   ├── create_processed_tables.sql
│   └── example_queries.sql  # Useful analytics queries
│
├── main.py                  # Original standalone script (for reference)
├── QUICKSTART.md           # 5-minute setup guide
├── DEPLOYMENT_GUIDE.md     # Complete deployment documentation
└── README.md               # This file
```

## 💻 Usage

### Query Your Data

```sql
-- View customers
SELECT * FROM `stripe_processed.customers` LIMIT 10;

-- Active subscriptions by plan
SELECT 
  plan_name, 
  COUNT(*) as count, 
  SUM(amount) as mrr 
FROM `stripe_processed.subscriptions` 
WHERE status = 'active'
GROUP BY plan_name;

-- MRR by plan
SELECT 
  plan_name,
  subscription_interval,
  COUNT(*) as subscriptions,
  SUM(amount) as mrr
FROM `stripe_processed.subscriptions`
WHERE status = 'active'
GROUP BY plan_name, subscription_interval
ORDER BY mrr DESC;
```

📊 **More Queries**: See [sql/example_queries.sql](sql/example_queries.sql)

### Manual Operations

```bash
# Trigger sync manually
gcloud scheduler jobs run stripe-bigquery-daily-sync --location=us-central1

# View Cloud Function logs
gcloud functions logs read stripe-bigquery-sync --region=us-central1 --gen2 --limit=50

# Check sync status
bq query --use_legacy_sql=false \
  'SELECT * FROM `stripe_metadata.sync_history` ORDER BY sync_completed_at DESC LIMIT 5'

# Pause scheduled sync
gcloud scheduler jobs pause stripe-bigquery-daily-sync --location=us-central1

# Resume scheduled sync
gcloud scheduler jobs resume stripe-bigquery-daily-sync --location=us-central1
```

## 🔒 Security

- ✅ **Stripe API key** stored in Google Secret Manager (encrypted at rest)
- ✅ **Service account** with least-privilege IAM permissions
- ✅ **No hardcoded credentials** in code or config files
- ✅ **Audit logging** enabled on all GCP resources
- ✅ **HTTPS-only** communication between all services

## 💰 Cost Breakdown

For typical small business usage (< 10,000 customers):

| Service | Monthly Cost | Notes |
|---------|-------------|-------|
| Cloud Functions | $0.00 - $0.40 | Free tier: 2M invocations/month (using 30-60) |
| Cloud Scheduler | $0.00 | Free tier: 3 jobs (using 1) |
| BigQuery Storage | $0.00 - $0.20 | Free tier: 10GB (typical usage: 1-5GB) |
| BigQuery Queries | $0.00 | Free tier: 1TB/month (typical: < 1GB) |
| Secret Manager | $0.00 | Free tier: 6 secrets (using 1) |
| **TOTAL** | **< $1/month** | Usually within free tier |

## 📈 Monitoring

### View Sync History

```sql
SELECT 
  entity_type,
  last_sync_timestamp,
  records_synced,
  status,
  sync_completed_at
FROM `stripe_metadata.sync_history`
ORDER BY sync_completed_at DESC
LIMIT 10;
```

### Check Data Freshness

```sql
SELECT 
  'customers' as table,
  COUNT(*) as records,
  MAX(ingested_at) as last_update,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(ingested_at), HOUR) as hours_old
FROM `stripe_processed.customers`
UNION ALL
SELECT 'subscriptions', COUNT(*), MAX(ingested_at), 
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(ingested_at), HOUR)
FROM `stripe_processed.subscriptions`;
```

### Cloud Function Metrics

View in GCP Console:
1. Navigation Menu → Cloud Functions
2. Click `stripe-bigquery-sync`
3. View **Metrics** tab for:
   - Invocations per day
   - Execution time
   - Error rate
   - Memory usage

## 🔧 Configuration

### Change Sync Schedule

```bash
# Change to 8:00 AM UTC
gcloud scheduler jobs update http stripe-bigquery-daily-sync \
  --location=us-central1 \
  --schedule="0 8 * * *"

# Run every 6 hours
gcloud scheduler jobs update http stripe-bigquery-daily-sync \
  --location=us-central1 \
  --schedule="0 */6 * * *"
```

### Sync Specific Entity Types

Trigger function with JSON payload:

```bash
# Sync only customers
curl -X POST <FUNCTION_URL> \
  -H "Content-Type: application/json" \
  -d '{"entities": ["customers"]}'

# Sync customers and subscriptions only
curl -X POST <FUNCTION_URL> \
  -H "Content-Type: application/json" \
  -d '{"entities": ["customers", "subscriptions"]}'
```

## 🐛 Troubleshooting

### Pipeline isn't syncing data

1. **Check Cloud Function logs**:
   ```bash
   gcloud functions logs read stripe-bigquery-sync --region=us-central1 --gen2 --limit=100
   ```

2. **Verify Stripe API key**:
   ```bash
   gcloud secrets versions access latest --secret=stripe-api-key
   ```

3. **Check sync history**:
   ```sql
   SELECT * FROM `stripe_metadata.sync_history` 
   WHERE status = 'failed' 
   ORDER BY sync_completed_at DESC;
   ```

### Permission errors

```bash
# Re-run IAM setup
PROJECT_ID=$(gcloud config get-value project)
SERVICE_ACCOUNT="stripe-sync-sa@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/bigquery.dataEditor"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/bigquery.jobUser"
```

### Function timeout

```bash
# Increase timeout to 9 minutes
gcloud functions deploy stripe-bigquery-sync \
  --gen2 \
  --timeout=540s \
  --region=us-central1
```

## 🎓 Example Use Cases

1. **Revenue Analytics**: Track MRR, churn, cohort analysis
2. **Customer Segmentation**: Analyze by geography, plan type, lifetime value
3. **Financial Reporting**: Automate monthly/quarterly revenue reports
4. **Alerting**: Set up alerts for failed payments, churned subscriptions
5. **Data Science**: Feed ML models for churn prediction, LTV forecasting
6. **Dashboards**: Build executive dashboards in Data Studio/Looker

## 🛠️ Extending the Pipeline

### Add More Stripe Entities

1. Update `stripe_client.py` to add new endpoint
2. Create table schema in `sql/create_processed_tables.sql`
3. Add transformation logic in `bigquery_client.py`
4. Deploy updated function

### Add Data Transformations

Create views or scheduled queries in BigQuery:

```sql
-- Example: Create MRR summary view
CREATE VIEW stripe_processed.mrr_summary AS
SELECT 
  DATE_TRUNC(current_period_start, MONTH) as month,
  SUM(amount) as mrr,
  COUNT(*) as subscription_count
FROM stripe_processed.subscriptions
WHERE status = 'active'
GROUP BY month;
```

## 📚 Additional Resources

- [Stripe API Documentation](https://stripe.com/docs/api)
- [BigQuery Documentation](https://cloud.google.com/bigquery/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Cloud Scheduler Documentation](https://cloud.google.com/scheduler/docs)

## 🤝 Contributing

Contributions welcome! Areas for enhancement:

- [ ] Add support for more Stripe entities (charges, refunds, disputes)
- [ ] Implement change data capture (CDC) for updates
- [ ] Add data quality tests
- [ ] Create pre-built Data Studio templates
- [ ] Add monitoring/alerting CloudFormation
- [ ] Support for multiple Stripe accounts

## 📝 License

MIT License - see LICENSE file for details

## 🆘 Support

- **Documentation**: Check [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) and [QUICKSTART.md](QUICKSTART.md)
- **Logs**: View Cloud Function logs for detailed error messages
- **Sync Status**: Query `stripe_metadata.sync_history` table
- **Issues**: Review GCP quotas and service limits

---

**Made with ❤️ for data-driven teams**

Deploy once, analyze forever. 🚀
