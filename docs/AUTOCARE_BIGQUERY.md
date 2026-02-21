# AutoCare Data in BigQuery + Unified Customer View

This document describes how AutoCare API data is stored in BigQuery (raw + processed) and how it is combined with Stripe data into a **unified customer** view.

## Overview

| Layer | Stripe | AutoCare |
|-------|--------|----------|
| **Raw** | `stripe_raw.customers_raw`, `subscriptions_raw` | `autocare_raw.tiers_raw`, `autocare_raw.marketing_data_raw` |
| **Processed** | `stripe_processed.customers`, `subscriptions` | `autocare_processed.tiers`, `marketing_customers`, `marketing_subscriptions`, `marketing_sessions` |
| **Metadata** | `stripe_metadata.sync_history` | `autocare_metadata.sync_history` |
| **Unified** | — | **`stripe_processed.unified_customers`** (VIEW), **`unified.customers`** (table, refreshed from view), **`bi.unified_customer_360_snapshot`** (flat BI table) |

**Join key:** Stripe `customer_id` = AutoCare `billing_id` (both are Stripe `cus_*` IDs).

---

## 1. AutoCare data in BigQuery

### 1.1 Raw tables

- **`autocare_raw.tiers_raw`**  
  One row per product from `v1/marketing/tiers`. Columns: `id` (product id), `json_data`, `ingested_at`.

- **`autocare_raw.marketing_data_raw`**  
  One row per item from `v1/marketing/data` (mix of customer and session records). Columns: `id`, `record_type` ('customer' | 'session'), `json_data`, `ingested_at`.

### 1.2 Processed tables

- **`autocare_processed.tiers`**  
  Flattened membership products: `product_id`, `name`, `product_key`, `perks`, `refund_required`, `validation_rules`, etc.

- **`autocare_processed.marketing_customers`**  
  One row per distinct customer: `client_id`, `billing_id` (Stripe `cus_*`), `email`, `first_name`, `last_name`, `phone_number`, `customer_created_date`.

- **`autocare_processed.marketing_subscriptions`**  
  One row per subscription: `subscription_id`, `client_id`, `billing_id`, `status`, `product_id`, `car_ids` (JSON array).

- **`autocare_processed.marketing_sessions`**  
  One row per usage/session event: `session_id`, `session_date`, `session_type`, `session_description`, `location_id`, `location_name`, etc.

- **`autocare_processed.marketing_cars`**  
  One row per car (from customers’ `cars[]`): `car_id`, `client_id`, `billing_id`, `json_data` (full object), plus `make`, `model`, `year`, `license_plate`, `color`, `vin`.

### 1.3 Sync flow

1. **Login:** `POST api/login` with email/password → JWT.
2. **Fetch:** `GET v1/marketing/tiers` and `GET v1/marketing/data` with `Authorization: Bearer <token>`.
3. **Raw:** Append to `autocare_raw.tiers_raw` and `autocare_raw.marketing_data_raw`.
4. **Processed:** Replace (TRUNCATE + insert) `autocare_processed.tiers` and the three marketing_* tables.
5. **Metadata:** Append a row to `autocare_metadata.sync_history` for each run.

The Cloud Function can run this when the HTTP request body includes `"sync_autocare": true`. Credentials are read from env vars:

- `AUTOCARE_API_EMAIL`
- `AUTOCARE_API_PASSWORD`

---

## 2. Unified customer view and tables

**View:** `stripe_processed.unified_customers`

- **One row per customer, no duplications.** Join: `stripe_processed.customers` LEFT JOIN AutoCare customer on `billing_id = customer_id`.
- **Stripe:** All customer columns (customer_id, email, name, phone, address, currency, balance, delinquent, created, etc.).
- **AutoCare profile:** All marketing_customer columns (autocare_client_id, autocare_email, autocare_first_name, autocare_last_name, autocare_phone, autocare_customer_created_date, etc.).
- **Unified contact:** `email`, `name`, `phone` = COALESCE(Stripe, AutoCare).
- **Stripe subscriptions:** `stripe_subscriptions` — ARRAY of STRUCT with all subscription fields (subscription_id, status, plan_name, product_id, current_period_start/end, amount, etc.).
- **Cars:** `cars` — ARRAY of STRUCT with all car fields (car_id, client_id, billing_id, json_data, make, model, year, license_plate, color, vin, updated_at, ingested_at).
- **Sessions:** `sessions` — ARRAY of STRUCT with all session fields (session_id, client_id, session_date, session_type, session_description, location_id, location_name, location_is_active, etc.).
- **AutoCare subscriptions + tiers:** `autocare_subscriptions_with_tiers` — ARRAY of STRUCT with all subscription fields plus full tier fields (tier_name, product_key, perks, refund_required, validation_rules, taxable_amount, etc.).

So you get **one row per Stripe customer** with complete cars, sessions, and subscriptions (with tier details), no duplicated customer rows.

**Table:** `unified.customers` — Materialized from the view by the Cloud Function after each sync. Same schema as the view; used as the source for the BI table.

**BI table:** `bi.unified_customer_360_snapshot` — Flat, one row per customer, with “latest” subscription/session/car and counts (no arrays). Refreshed by the Cloud Function after `unified.customers`. See [BI_CUSTOMER_360.md](BI_CUSTOMER_360.md).

### Creating the view

1. Create AutoCare datasets and tables (see below).
2. Run the unified view SQL once, after Stripe and AutoCare processed tables exist:

```bash
# Replace PROJECT_ID in sql/create_unified_customer_view.sql with your project ID, then:
bq query --use_legacy_sql=false < sql/create_unified_customer_view.sql
```

Or in BigQuery Console: open `sql/create_unified_customer_view.sql`, replace `PROJECT_ID` with your GCP project ID, and run.

---

## 3. How to set up BigQuery for AutoCare

### 3.1 Create datasets

```bash
bq mk -d autocare_raw
bq mk -d autocare_processed
bq mk -d autocare_metadata
```

### 3.2 Create tables

Run in order:

```bash
bq query --use_legacy_sql=false < sql/create_autocare_raw_tables.sql
bq query --use_legacy_sql=false < sql/create_autocare_processed_tables.sql
bq query --use_legacy_sql=false < sql/create_autocare_metadata_tables.sql
```

Or use the optional AutoCare section in `gcp-setup/create-tables.sh` if added.

### 3.3 Cloud Function env vars (for AutoCare sync)

Set when deploying or updating the function:

```bash
gcloud functions deploy stripe-bigquery-sync ... \
  --set-env-vars "AUTOCARE_API_EMAIL=api_admin@test.com,AUTOCARE_API_PASSWORD=YourPassword"
```

Or use Secret Manager and read them in code (same pattern as Stripe/Replit).

---

## 4. Triggering AutoCare sync and unified/BI refresh

- **With Stripe sync (same request):**  
  POST to the Cloud Function with body:  
  `{"sync_autocare": true}`  
  This runs: AutoCare sync first → Stripe entities (customers, subscriptions) → **unified.customers** (from view) → **bi.unified_customer_360_snapshot** (full CTE query).

- **AutoCare only:**  
  Send `{"entities": [], "sync_autocare": true}` so only AutoCare runs; unified and BI tables are still refreshed at the end.

- **Scheduler:**  
  Use one Cloud Scheduler job that POSTs with `sync_autocare: true` (and optionally `entities`) so both Stripe and AutoCare sync, then unified + BI tables are updated.

---

## 5. Summary

| Goal | Solution |
|------|----------|
| Store AutoCare data in BigQuery | Raw in `autocare_raw.*`, processed in `autocare_processed.*` |
| Same pattern as Stripe | Raw (append) + processed (replace) + metadata (append) |
| One place for “all user info” | View `stripe_processed.unified_customers`; table `unified.customers` (refreshed after sync) |
| Flat table for BI tools | `bi.unified_customer_360_snapshot` — one row per customer, latest sub/session/car + counts |
| Preferred contact fields | `email`, `name`, `phone` in the view use COALESCE(Stripe, AutoCare) |
