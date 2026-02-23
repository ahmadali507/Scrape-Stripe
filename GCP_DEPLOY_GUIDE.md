# Deploy the new structure to GCP (scripts only)

Use this guide to deploy the BigQuery tables/datasets and the Cloud Function using the provided scripts. Secrets and service roles are assumed already set up.

---

## 1. Set GCP project

```bash
gcloud config set project YOUR_PROJECT_ID
```

---

## 2. Create BigQuery tables and datasets

From the repo root:

```bash
cd gcp-setup
chmod +x *.sh
./create-tables.sh
```

This creates Stripe, AutoCare, unified, and BI in one go:

- **Stripe:** `stripe_metadata`, `stripe_raw`, `stripe_processed` and their tables
- **AutoCare:** `autocare_raw`, `autocare_processed`, `autocare_metadata` and their tables
- **Unified / BI:** datasets `unified` and `bi` (tables are filled by the Cloud Function)

---

## 3. Create the unified_customers view (once)

1. Open `sql/create_unified_customer_view.sql`.
2. Replace every `PROJECT_ID` with your GCP project ID.
3. Run the script in BigQuery:

   ```bash
   bq query --use_legacy_sql=false --project_id=YOUR_PROJECT_ID < sql/create_unified_customer_view.sql
   ```

   Or run the script in the BigQuery Console.

---

## 4. Deploy the Cloud Function

```bash
cd gcp-setup
./deploy-function.sh
```

This copies the BI snapshot SQL from `sql/` into `cloud-function/sql/`, then deploys the function. The function will refresh `unified.customers` and `bi.unified_customer_360_snapshot` after each sync.

---

## 5. Populate the tables (Stripe + AutoCare)

Data is pulled from Stripe and AutoCare only when the Cloud Function runs. Do the following so tables get filled.

### Prerequisites

- **Stripe:** Secret `stripe-api-key` must exist in Secret Manager and the function’s service account must have access. The deploy script sets `GOOGLE_CLOUD_PROJECT` so the function can read it.
- **AutoCare:** The function needs `AUTOCARE_API_EMAIL` and `AUTOCARE_API_PASSWORD`. You can either set them as env vars when deploying, or store them in Secret Manager so you never need to set them again:
  - **Secret Manager (recommended):** Run `./setup-secrets.sh` (it creates `autocare-api-email` and `autocare-api-password` and grants the function access). Add versions with your values:  
    `echo -n 'your-email' | gcloud secrets versions add autocare-api-email --data-file=-`  
    `echo -n 'your-password' | gcloud secrets versions add autocare-api-password --data-file=-`  
    The function reads these when the env vars are not set.
  - **Env vars:** Set when deploying or in Cloud Console (Cloud Functions → Edit → Environment variables).
- **Replit webhook:** Similarly, use Secret Manager secrets `replit-webhook-url` and `replit-webhook-secret` so the function can send new customers without setting env vars at deploy.

### Trigger a full sync (Stripe + AutoCare)

Call the function with `sync_autocare: true` so it fetches from both Stripe and AutoCare, then writes to raw/processed and refreshes unified/BI:

```bash
# Replace with your function URL, or get it with:
# gcloud functions describe stripe-bigquery-sync --region=us-central1 --gen2 --format='value(serviceConfig.uri)'

curl -X POST "https://YOUR_REGION-YOUR_PROJECT.cloudfunctions.net/stripe-bigquery-sync" \
  -H "Content-Type: application/json" \
  -d '{"sync_autocare": true}'
```

- **Stripe:** Fetches customers and subscriptions (incremental from last sync), writes to `stripe_raw.*` and `stripe_processed.*`.
- **AutoCare:** Fetches tiers and marketing data (full), writes to `autocare_raw.*` and `autocare_processed.*`.
- Then the function refreshes `unified.customers` and `bi.unified_customer_360_snapshot`.

### Trigger only Stripe (no AutoCare)

```bash
curl -X POST "YOUR_FUNCTION_URL" -H "Content-Type: application/json"
# or
curl -X POST "YOUR_FUNCTION_URL" -H "Content-Type: application/json" -d '{}'
```

### Check that data was written

- **Stripe:** `stripe_metadata.sync_history` (last run per entity), `stripe_processed.customers` / `stripe_processed.subscriptions`.
- **AutoCare:** `autocare_metadata.sync_history`, `autocare_processed.tiers`, `autocare_processed.marketing_customers`, etc.
- **Unified/BI:** After a successful run, `unified.customers` and `bi.unified_customer_360_snapshot` (only if the view `stripe_processed.unified_customers` exists; see step 3).

If tables stay empty, check Cloud Function logs for errors (e.g. missing Stripe secret, AutoCare credentials, or API errors).

---

## If you see "Table unified.customers was not found" (404)

The function builds `unified.customers` from the **view** `stripe_processed.unified_customers`. If that view doesn’t exist, the table is never created and the BI step fails.

1. Run **Step 3** above: replace `PROJECT_ID` in `sql/create_unified_customer_view.sql` with your project ID (e.g. `hitech-484412`) and run the script in BigQuery.
2. Trigger a sync again. The function will create `unified.customers` from the view, then refresh `bi.unified_customer_360_snapshot`.

---

## Summary

| Step | Script / action |
|------|------------------|
| 1 | `gcloud config set project YOUR_PROJECT_ID` |
| 2 | `cd gcp-setup && chmod +x *.sh && ./create-tables.sh` |
| 3 | Replace `PROJECT_ID` in `sql/create_unified_customer_view.sql`, then run it in BigQuery |
| 4 | `cd gcp-setup && ./deploy-function.sh` (optionally set `AUTOCARE_API_EMAIL` and `AUTOCARE_API_PASSWORD` first) |
| 5 | Trigger sync to populate tables: `curl -X POST YOUR_FUNCTION_URL -H "Content-Type: application/json" -d '{"sync_autocare": true}'` |
