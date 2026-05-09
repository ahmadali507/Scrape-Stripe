<p align="center">
  <img src="https://capsule-render.vercel.app/api?type=waving&color=0:4F46E5,50:7C3AED,100:06B6D4&height=200&section=header&text=Scrape-Stripe&fontSize=70&fontColor=ffffff&fontAlignY=38&desc=Stripe%20%E2%86%92%20BigQuery%20%7C%20Serverless%20ETL%20Pipeline&descAlignY=58&descSize=20&animation=fadeIn" width="100%"/>
</p>

<p align="center">
  <a href="https://github.com/ahmadali507/Scrape-Stripe">
    <img src="https://readme-typing-svg.demolab.com?font=Fira+Code&weight=600&size=22&pause=1000&color=7C3AED&center=true&vCenter=true&width=700&lines=Automated+Daily+Stripe+%E2%86%92+BigQuery+Sync;Incremental+Loading+%7C+Zero+Data+Loss;Serverless+%7C+Scalable+%7C+%3C%241%2Fmonth;Deploy+in+5+Minutes+on+Google+Cloud" alt="Typing SVG" />
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Python-3.11+-3776AB?style=for-the-badge&logo=python&logoColor=white"/>
  <img src="https://img.shields.io/badge/Google_Cloud-4285F4?style=for-the-badge&logo=google-cloud&logoColor=white"/>
  <img src="https://img.shields.io/badge/BigQuery-669DF6?style=for-the-badge&logo=google-bigquery&logoColor=white"/>
  <img src="https://img.shields.io/badge/Stripe-635BFF?style=for-the-badge&logo=stripe&logoColor=white"/>
  <img src="https://img.shields.io/badge/Serverless-FD5750?style=for-the-badge&logo=serverless&logoColor=white"/>
  <img src="https://img.shields.io/badge/License-MIT-22C55E?style=for-the-badge"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Cloud_Functions-Deployed-4285F4?style=flat-square&logo=google-cloud"/>
  <img src="https://img.shields.io/badge/Cloud_Scheduler-Daily_6AM_UTC-7C3AED?style=flat-square&logo=google-cloud"/>
  <img src="https://img.shields.io/badge/Cost-Under%20%241%2Fmo-22C55E?style=flat-square"/>
  <img src="https://img.shields.io/badge/Setup-5_Minutes-F59E0B?style=flat-square"/>
</p>

<br/>

<p align="center">
  <b>Scrape-Stripe</b> is a production-ready, fully serverless ETL pipeline that automatically syncs your Stripe data — customers, subscriptions, and invoices — into Google BigQuery every single day. No servers to manage. No data loss. Ready for analytics from day one.
</p>

---

## 📋 Table of Contents

<p align="center">
  <a href="#-features"><img src="https://img.shields.io/badge/Features-7C3AED?style=flat-square"/></a>
  <a href="#-architecture"><img src="https://img.shields.io/badge/Architecture-4F46E5?style=flat-square"/></a>
  <a href="#-what-gets-synced"><img src="https://img.shields.io/badge/Data%20Model-06B6D4?style=flat-square"/></a>
  <a href="#-quick-start"><img src="https://img.shields.io/badge/Quick%20Start-22C55E?style=flat-square"/></a>
  <a href="#-project-structure"><img src="https://img.shields.io/badge/Structure-F59E0B?style=flat-square"/></a>
  <a href="#-usage"><img src="https://img.shields.io/badge/Usage-EF4444?style=flat-square"/></a>
  <a href="#-security"><img src="https://img.shields.io/badge/Security-DC2626?style=flat-square"/></a>
  <a href="#-cost-breakdown"><img src="https://img.shields.io/badge/Cost-16A34A?style=flat-square"/></a>
  <a href="#-monitoring"><img src="https://img.shields.io/badge/Monitoring-0EA5E9?style=flat-square"/></a>
  <a href="#-troubleshooting"><img src="https://img.shields.io/badge/Troubleshooting-9CA3AF?style=flat-square"/></a>
</p>

---

## ✨ Features

<table>
  <tr>
    <td align="center" width="200">
      <img src="https://img.shields.io/badge/%E2%9A%A1-Automated_Daily_Sync-7C3AED?style=for-the-badge" /><br/>
      <sub>Runs every morning at 6:00 AM UTC via Cloud Scheduler — fully hands-free.</sub>
    </td>
    <td align="center" width="200">
      <img src="https://img.shields.io/badge/%F0%9F%94%84-Incremental_Loading-4F46E5?style=for-the-badge" /><br/>
      <sub>Only fetches new and updated records since the last sync. No full re-pulls.</sub>
    </td>
    <td align="center" width="200">
      <img src="https://img.shields.io/badge/%F0%9F%93%9C-Complete_Audit_Trail-06B6D4?style=for-the-badge" /><br/>
      <sub>Stores raw JSON alongside clean processed tables for full data lineage.</sub>
    </td>
  </tr>
  <tr>
    <td align="center" width="200">
      <img src="https://img.shields.io/badge/%F0%9F%92%B8-Under_%241%2Fmonth-22C55E?style=for-the-badge" /><br/>
      <sub>Fits entirely within GCP's free tier for typical small business usage.</sub>
    </td>
    <td align="center" width="200">
      <img src="https://img.shields.io/badge/%F0%9F%94%92-Secret_Manager-EF4444?style=for-the-badge" /><br/>
      <sub>API keys encrypted at rest in GCP Secret Manager. Zero hardcoded credentials.</sub>
    </td>
    <td align="center" width="200">
      <img src="https://img.shields.io/badge/%E2%98%81%EF%B8%8F-Fully_Serverless-F59E0B?style=for-the-badge" /><br/>
      <sub>No VMs, no Kubernetes. Cloud Functions scale to zero between runs.</sub>
    </td>
  </tr>
  <tr>
    <td align="center" width="200">
      <img src="https://img.shields.io/badge/%F0%9F%93%88-Scalable-0EA5E9?style=for-the-badge" /><br/>
      <sub>Handles datasets from early-stage startups to large enterprises.</sub>
    </td>
    <td align="center" width="200">
      <img src="https://img.shields.io/badge/%F0%9F%93%8A-Query_Ready-9333EA?style=for-the-badge" /><br/>
      <sub>Clean, flattened BigQuery tables immediately usable with Looker or Data Studio.</sub>
    </td>
    <td align="center" width="200">
      <img src="https://img.shields.io/badge/%F0%9F%8E%AF-5_Min_Deploy-16A34A?style=for-the-badge" /><br/>
      <sub>One-line GCP Cloud Shell setup script. No manual configuration needed.</sub>
    </td>
  </tr>
</table>

---

## 🏗️ Architecture

<p align="center">

```
╔═══════════════════════════════════════════════════════════════════╗
║                     SCRAPE-STRIPE PIPELINE                        ║
╚═══════════════════════════════════════════════════════════════════╝

    ┌─────────────────────────────┐
    │       Cloud Scheduler       │   ⏰  Triggers daily at 6 AM UTC
    │    Cron: "0 6 * * *"        │       (fully configurable)
    └──────────────┬──────────────┘
                   │  HTTP trigger
                   ▼
    ┌──────────────────────────┐         ┌──────────────────────┐
    │      Cloud Function      │────────▶│    Secret Manager    │
    │   (ETL Orchestrator)     │         │   stripe-api-key     │
    │                          │◀────────│   (encrypted key)    │
    └────────────┬─────────────┘         └──────────────────────┘
                 │
         ┌───────┴────────┐
         │                │
         ▼                ▼
  ┌─────────────┐  ┌──────────────┐
  │ Stripe API  │  │  AutoCare    │    📡  Incremental fetch
  │  /customers │  │     API      │        (only new/changed records)
  │  /subscr.   │  │  (optional)  │
  └──────┬──────┘  └──────┬───────┘
         └────────┬────────┘
                  ▼
    ┌─────────────────────────────────────────────────────┐
    │                    BIGQUERY                          │
    │                                                      │
    │   ┌──────────────────────────────────────────────┐  │
    │   │  stripe_raw        (Raw JSON Backup)         │  │
    │   │    • customers_raw    • subscriptions_raw    │  │
    │   └──────────────────────────────────────────────┘  │
    │                                                      │
    │   ┌──────────────────────────────────────────────┐  │
    │   │  stripe_processed  (Clean Analytics Tables)  │  │
    │   │    • customers        • subscriptions        │  │
    │   └──────────────────────────────────────────────┘  │
    │                                                      │
    │   ┌──────────────────────────────────────────────┐  │
    │   │  stripe_metadata   (Sync Tracking)           │  │
    │   │    • sync_history                            │  │
    │   └──────────────────────────────────────────────┘  │
    │                                                      │
    │   ┌──────────────────────────────────────────────┐  │
    │   │  unified           (Cross-Source View)       │  │
    │   │    • customers  (Stripe + AutoCare merged)   │  │
    │   └──────────────────────────────────────────────┘  │
    │                                                      │
    │   ┌──────────────────────────────────────────────┐  │
    │   │  bi                (Business Intelligence)   │  │
    │   │    • unified_customer_360_snapshot           │  │
    │   └──────────────────────────────────────────────┘  │
    └─────────────────────────────────────────────────────┘
```

</p>

---

## 📊 What Gets Synced

<div align="center">

| Stripe Entity | BigQuery Dataset | BigQuery Table | Key Fields |
|:---|:---|:---|:---|
| ![](https://img.shields.io/badge/Customers-635BFF?style=flat-square) | `stripe_processed` | `customers` | ID, email, name, address, phone, created date, billing info |
| ![](https://img.shields.io/badge/Subscriptions-06B6D4?style=flat-square) | `stripe_processed` | `subscriptions` | ID, customer, status, amount, plan, interval, period dates, cancellation info |
| ![](https://img.shields.io/badge/Raw_JSON-4F46E5?style=flat-square) | `stripe_raw` | `customers_raw`, `subscriptions_raw` | Full raw API responses for complete audit trail |
| ![](https://img.shields.io/badge/Sync_History-22C55E?style=flat-square) | `stripe_metadata` | `sync_history` | Entity type, timestamps, record count, status |
| ![](https://img.shields.io/badge/Unified_View-F59E0B?style=flat-square) | `unified` | `customers` | Cross-source merged view (Stripe + AutoCare) |
| ![](https://img.shields.io/badge/BI_Snapshot-EF4444?style=flat-square) | `bi` | `unified_customer_360_snapshot` | Executive-level 360 customer snapshot |

</div>

---

## 🚀 Quick Start

> **Total time required: ~5 minutes**

```bash
# Step 1: Open Google Cloud Shell and clone the repo
git clone https://github.com/ahmadali507/Scrape-Stripe.git
cd Scrape-Stripe/gcp-setup
chmod +x *.sh

# Step 2: One-line full setup
./setup.sh            # Enable APIs, create service account & datasets
./setup-secrets.sh    # Store Stripe API key in Secret Manager
./create-tables.sh    # Create all BigQuery table schemas
./deploy-function.sh  # Deploy Cloud Function (ETL logic)
./setup-scheduler.sh  # Schedule daily 6 AM UTC trigger

# Step 3: Verify everything is working
./test-pipeline.sh
```

> **That's it!** Your pipeline is live and syncing data every morning.

---

## 📁 Project Structure

```
Scrape-Stripe/
│
├── 📂 cloud-function/               # Core ETL Cloud Function
│   ├── 🐍 main.py                   # HTTP entry point & orchestrator
│   ├── 🐍 stripe_client.py          # Stripe API client (incremental sync)
│   ├── 🐍 bigquery_client.py        # BigQuery write & upsert operations
│   ├── 🐍 autocare_client.py        # AutoCare API integration
│   ├── 🐍 receiver_client.py        # GoHighLevel CRM receiver
│   ├── 🐍 job.py                    # Cloud Run Job entrypoint
│   ├── 📄 requirements.txt          # Python dependencies
│   ├── 🐳 Dockerfile                # Container image for Cloud Run Job
│   └── 🚫 .gcloudignore             # Deployment exclusions
│
├── 📂 gcp-setup/                    # Automated GCP provisioning scripts
│   ├── 🔧 setup.sh                  # Enable APIs + create service account
│   ├── 🔑 setup-secrets.sh          # Store Stripe key in Secret Manager
│   ├── 🗄️  create-tables.sh          # Provision all BigQuery tables
│   ├── 🚀 deploy-function.sh        # Deploy/redeploy Cloud Function
│   ├── ⏰ setup-scheduler.sh        # Configure Cloud Scheduler job
│   ├── 🔗 full-setup.sh             # End-to-end provisioning (all steps)
│   ├── 🧹 cleanup-job-and-scheduler.sh  # Tear down scheduler & job
│   └── 🧪 test-pipeline.sh          # Smoke test the deployed pipeline
│
├── 📂 sql/                          # BigQuery schema definitions
│   ├── create_raw_tables.sql        # Raw JSON backup tables
│   ├── create_processed_tables.sql  # Clean analytics tables
│   ├── create_metadata_tables.sql   # Sync tracking tables
│   ├── create_unified_customer_view.sql  # Cross-source unified view
│   ├── create_bi_customer_360_snapshot.sql  # BI executive snapshot
│   └── 📊 example_queries.sql       # Ready-to-run analytics queries
│
├── 📂 docs/                         # Extended documentation
│   ├── AUTOCARE_BIGQUERY.md
│   └── BI_CUSTOMER_360.md
│
├── 🐍 main.py                       # Standalone script (local reference)
├── 🧪 test_stripe_api.py            # Stripe API test suite
├── 🧪 test_autocare_api.py          # AutoCare API test suite
├── 🔀 cross_match.py                # Cross-source customer matching
├── 📄 requirements.txt              # Top-level Python dependencies
├── 📖 GCP_DEPLOY_GUIDE.md           # Full deployment walkthrough
├── 🔁 CICD_SETUP.md                 # CI/CD pipeline configuration
└── 📘 README.md                     # This file
```

---

## 💻 Usage

### Query Your Data

<details>
<summary><b>View Customers</b></summary>

```sql
SELECT
  id,
  email,
  name,
  created_at,
  billing_city,
  billing_country
FROM `stripe_processed.customers`
ORDER BY created_at DESC
LIMIT 10;
```

</details>

<details>
<summary><b>Monthly Recurring Revenue (MRR) by Plan</b></summary>

```sql
SELECT
  plan_name,
  subscription_interval,
  COUNT(*)    AS active_subscriptions,
  SUM(amount) AS mrr
FROM `stripe_processed.subscriptions`
WHERE status = 'active'
GROUP BY plan_name, subscription_interval
ORDER BY mrr DESC;
```

</details>

<details>
<summary><b>Churn Analysis</b></summary>

```sql
SELECT
  DATE_TRUNC(canceled_at, MONTH) AS churn_month,
  COUNT(*)                        AS churned_subscriptions,
  SUM(amount)                     AS lost_mrr
FROM `stripe_processed.subscriptions`
WHERE status = 'canceled'
  AND canceled_at IS NOT NULL
GROUP BY churn_month
ORDER BY churn_month DESC;
```

</details>

<details>
<summary><b>Check Data Freshness</b></summary>

```sql
SELECT
  'customers'     AS table_name,
  COUNT(*)        AS total_records,
  MAX(ingested_at) AS last_synced,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(ingested_at), HOUR) AS hours_since_sync
FROM `stripe_processed.customers`
UNION ALL
SELECT
  'subscriptions',
  COUNT(*),
  MAX(ingested_at),
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(ingested_at), HOUR)
FROM `stripe_processed.subscriptions`;
```

</details>

<details>
<summary><b>View Sync History</b></summary>

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

</details>

---

### Manual Operations

```bash
# Trigger a manual sync right now
gcloud scheduler jobs run stripe-bigquery-daily-sync \
  --location=us-central1

# Stream Cloud Function logs
gcloud functions logs read stripe-bigquery-sync \
  --region=us-central1 --gen2 --limit=50

# Sync only specific entities
curl -X POST <FUNCTION_URL> \
  -H "Content-Type: application/json" \
  -d '{"entities": ["customers", "subscriptions"]}'

# Pause the daily schedule
gcloud scheduler jobs pause stripe-bigquery-daily-sync \
  --location=us-central1

# Resume the daily schedule
gcloud scheduler jobs resume stripe-bigquery-daily-sync \
  --location=us-central1

# Change sync schedule (e.g. to 8 AM UTC)
gcloud scheduler jobs update http stripe-bigquery-daily-sync \
  --location=us-central1 \
  --schedule="0 8 * * *"
```

---

## 🔒 Security

<div align="center">

| Control | Implementation | Status |
|:---|:---|:---:|
| **Secret storage** | Stripe API key stored in GCP Secret Manager (encrypted at rest and in transit) | ✅ |
| **Least privilege** | Dedicated service account with only `bigquery.dataEditor` and `bigquery.jobUser` roles | ✅ |
| **No hardcoded credentials** | Zero secrets in code, config files, or environment variables at deploy time | ✅ |
| **Audit logging** | GCP audit logs enabled on all resources (Cloud Function, BigQuery, Secret Manager) | ✅ |
| **Encrypted transport** | HTTPS-only communication between Cloud Function, Stripe API, and BigQuery | ✅ |

</div>

---

## 💰 Cost Breakdown

> For typical small business usage with fewer than 10,000 customers:

<div align="center">

| GCP Service | Free Tier | Typical Usage | Monthly Cost |
|:---|:---|:---|:---:|
| **Cloud Functions** | 2M invocations/month | ~30–60 invocations | `$0.00` |
| **Cloud Scheduler** | 3 jobs free | 1 job | `$0.00` |
| **BigQuery Storage** | 10 GB free | 1–5 GB | `$0.00 – $0.20` |
| **BigQuery Queries** | 1 TB/month free | < 1 GB | `$0.00` |
| **Secret Manager** | 6 secrets free | 1 secret | `$0.00` |
| **Total** | | | **`< $1.00 / mo`** |

</div>

---

## 📈 Monitoring

### Cloud Function Metrics

Navigate to **GCP Console → Cloud Functions → `stripe-bigquery-sync` → Metrics** to view invocation count, execution duration, error rate, and memory utilization.

```sql
-- Recent sync status at a glance
SELECT
  entity_type,
  status,
  records_synced,
  sync_completed_at
FROM `stripe_metadata.sync_history`
ORDER BY sync_completed_at DESC
LIMIT 10;

-- Failed syncs requiring attention
SELECT *
FROM `stripe_metadata.sync_history`
WHERE status = 'failed'
ORDER BY sync_completed_at DESC;
```

---

## 🎓 Example Use Cases

<div align="center">

| Use Case | Description |
|:---|:---|
| **Revenue Analytics** | Track MRR, ARR, churn rate, and cohort analysis directly in BigQuery or Looker |
| **Customer Segmentation** | Slice by geography, plan tier, lifetime value, or acquisition channel |
| **Financial Reporting** | Automate monthly and quarterly revenue report generation |
| **Alerting** | Trigger alerts on failed payments, cancelled subscriptions, or revenue drops |
| **Churn Prediction** | Feed clean subscription history into ML models for LTV and churn forecasting |
| **Executive Dashboards** | Power real-time dashboards in Looker Studio, Metabase, or Tableau |
| **Customer 360** | Combine Stripe billing data with AutoCare or CRM data via the unified view |

</div>

---

## 🛠️ Extending the Pipeline

<details>
<summary><b>Add More Stripe Entities</b></summary>

1. Add a new fetch method to `cloud-function/stripe_client.py`
2. Add the table schema to `sql/create_processed_tables.sql`
3. Add transformation and write logic to `cloud-function/bigquery_client.py`
4. Redeploy the function:
   ```bash
   cd gcp-setup && ./deploy-function.sh
   ```

</details>

<details>
<summary><b>Create Derived Views or Scheduled Queries</b></summary>

```sql
-- Example: MRR summary view
CREATE OR REPLACE VIEW stripe_processed.mrr_summary AS
SELECT
  DATE_TRUNC(current_period_start, MONTH) AS month,
  SUM(amount)                              AS mrr,
  COUNT(*)                                 AS subscription_count
FROM stripe_processed.subscriptions
WHERE status = 'active'
GROUP BY month
ORDER BY month DESC;
```

</details>

---

## 🐛 Troubleshooting

<details>
<summary><b>Pipeline isn't syncing data</b></summary>

```bash
# Check Cloud Function execution logs
gcloud functions logs read stripe-bigquery-sync \
  --region=us-central1 --gen2 --limit=100

# Verify the Stripe API key is accessible
gcloud secrets versions access latest --secret=stripe-api-key

# Inspect failed syncs in BigQuery
bq query --use_legacy_sql=false \
  "SELECT * FROM \`stripe_metadata.sync_history\`
   WHERE status = 'failed'
   ORDER BY sync_completed_at DESC LIMIT 5"
```

</details>

<details>
<summary><b>IAM / Permission errors</b></summary>

```bash
PROJECT_ID=$(gcloud config get-value project)
SERVICE_ACCOUNT="stripe-sync-sa@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/bigquery.dataEditor"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/bigquery.jobUser"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/secretmanager.secretAccessor"
```

</details>

<details>
<summary><b>Function timeout on large datasets</b></summary>

```bash
gcloud functions deploy stripe-bigquery-sync \
  --gen2 \
  --timeout=540s \
  --region=us-central1
```

</details>

---

## 🤝 Contributing

Contributions are welcome. To get started:

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Commit your changes: `git commit -m 'feat: add my feature'`
4. Push to your branch: `git push origin feature/my-feature`
5. Open a Pull Request against `main`

**Open contribution areas:**

- [ ] Support for additional Stripe entities (charges, refunds, disputes, events)
- [ ] Change Data Capture (CDC) for real-time streaming ingestion
- [ ] Data quality checks and automated test suite
- [ ] Pre-built Looker Studio / Metabase dashboard templates
- [ ] Multi-account Stripe support
- [ ] Terraform module for infrastructure provisioning

---

## 📚 Resources

<p align="center">
  <a href="https://stripe.com/docs/api">
    <img src="https://img.shields.io/badge/Stripe_API_Docs-635BFF?style=for-the-badge&logo=stripe&logoColor=white"/>
  </a>
  <a href="https://cloud.google.com/bigquery/docs">
    <img src="https://img.shields.io/badge/BigQuery_Docs-669DF6?style=for-the-badge&logo=google-bigquery&logoColor=white"/>
  </a>
  <a href="https://cloud.google.com/functions/docs">
    <img src="https://img.shields.io/badge/Cloud_Functions_Docs-4285F4?style=for-the-badge&logo=google-cloud&logoColor=white"/>
  </a>
  <a href="https://cloud.google.com/scheduler/docs">
    <img src="https://img.shields.io/badge/Cloud_Scheduler_Docs-34A853?style=for-the-badge&logo=google-cloud&logoColor=white"/>
  </a>
</p>

---

<p align="center">
  <img src="https://capsule-render.vercel.app/api?type=waving&color=0:06B6D4,50:7C3AED,100:4F46E5&height=120&section=footer&animation=fadeIn" width="100%"/>
</p>

<p align="center">
  Built by <a href="https://github.com/ahmadali507"><b>Ahmad Ali</b></a> &nbsp;·&nbsp; Deploy once. Analyze forever.
  <br/><br/>
  <a href="https://github.com/ahmadali507/Scrape-Stripe">
    <img src="https://img.shields.io/github/stars/ahmadali507/Scrape-Stripe?style=social" />
  </a>
  &nbsp;
  <a href="https://github.com/ahmadali507/Scrape-Stripe/fork">
    <img src="https://img.shields.io/github/forks/ahmadali507/Scrape-Stripe?style=social" />
  </a>
</p>
