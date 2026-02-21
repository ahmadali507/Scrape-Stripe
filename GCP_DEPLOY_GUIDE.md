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

## Summary

| Step | Script / action |
|------|------------------|
| 1 | `gcloud config set project YOUR_PROJECT_ID` |
| 2 | `cd gcp-setup && chmod +x *.sh && ./create-tables.sh` |
| 3 | Replace `PROJECT_ID` in `sql/create_unified_customer_view.sql`, then run it in BigQuery |
| 4 | `cd gcp-setup && ./deploy-function.sh` |
