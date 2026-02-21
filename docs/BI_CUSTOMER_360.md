# BI Table: unified_customer_360_snapshot

This document describes the **BI layer** of the pipeline: the flat, denormalized table `bi.unified_customer_360_snapshot`, built for BI tools (Looker, Tableau, Metabase, Power BI).

## Purpose

- **One row per customer** — no arrays, no nested structs.
- **Fully flattened** — “latest” subscription, session, car and all counts are scalar columns.
- **Fast reads** — no joins needed in the BI tool; ideal for dashboards and exports.

## Table

| Dataset | Table | Partition | Cluster |
|---------|--------|-----------|---------|
| `bi` | `unified_customer_360_snapshot` | `DATE(customer_since)` | `customer_id`, `email`, `current_tier_key` |

## Columns (summary)

| Group | Columns |
|-------|---------|
| **Identity** | `customer_id`, `autocare_client_id`, `email`, `name`, `phone`, `customer_since`, `autocare_created_at` |
| **Customer status** | `customer_status` — 'Active' \| 'Past Due' \| 'Churned' \| 'No Subscription' (from latest Stripe sub) |
| **Latest Stripe sub** | `latest_stripe_subscription_id`, `latest_stripe_sub_status`, `latest_plan_name`, `latest_plan_amount`, `latest_plan_currency`, `latest_plan_interval`, `latest_period_start`, `latest_period_end`, `canceling_at_period_end`, `latest_stripe_sub_created_at` |
| **Stripe sub counts** | `total_stripe_subscriptions`, `active_stripe_subscriptions`, `canceled_stripe_subscriptions` |
| **Latest AutoCare sub + tier** | `latest_autocare_subscription_id`, `latest_autocare_sub_status`, `current_tier_product_id`, `current_tier_name`, `current_tier_key`, `current_tier_perks`, `latest_autocare_sub_updated_at` |
| **AutoCare sub counts** | `total_autocare_subscriptions`, `distinct_tiers_used` |
| **Latest session** | `latest_session_id`, `latest_session_date`, `latest_session_type`, `latest_session_description`, `latest_session_location_id`, `latest_session_location` |
| **Session counts** | `total_sessions`, `first_session_date`, `last_session_date` |
| **Latest car** | `latest_car_id`, `latest_car_make`, `latest_car_model`, `latest_car_year`, `latest_car_license_plate`, `latest_car_color`, `latest_car_vin` |
| **Car counts** | `total_cars` |
| **Metadata** | `last_synced_at` |

## How it is built (CTEs)

The table is created with `CREATE OR REPLACE TABLE bi.unified_customer_360_snapshot AS` and a single SQL that uses these CTEs:

1. **uc** — Base row per customer from `unified.customers` (identity + `customer_since`, `autocare_created_at`, `last_synced_at`).
2. **latest_stripe_sub** — One row per `customer_id`: the “current” Stripe subscription (prefer `status = 'active'`, then most recent by `created`); `ROW_NUMBER() ... QUALIFY`-style logic.
3. **latest_autocare_sub** — One row per `billing_id`: latest AutoCare subscription by `updated_at`, joined to `autocare_processed.tiers` for tier name, key, perks.
4. **latest_session** — One row per `client_id`: latest session by `session_date` (and `session_id` tie-break).
5. **latest_car** — One row per `billing_id`: latest car by `updated_at`.
6. **subscription_counts** — Per `customer_id`: `COUNT(*)`, `COUNTIF(status='active')`, `COUNTIF(status='canceled')` from `stripe_processed.subscriptions`.
7. **autocare_sub_counts** — Per `billing_id`: `COUNT(*)`, `COUNT(DISTINCT product_id)` from `autocare_processed.marketing_subscriptions`.
8. **session_counts** — Per `client_id`: `COUNT(*)`, `MIN(session_date)`, `MAX(session_date)` from `autocare_processed.marketing_sessions`.
9. **car_counts** — Per `billing_id`: `COUNT(*)` from `autocare_processed.marketing_cars`.

All CTEs are **LEFT JOIN**ed back to `uc` so every customer has one row even when they have no subscriptions, sessions, or cars.

## When it is updated

- **After all syncing is done:** The Cloud Function updates **unified.customers** (from `stripe_processed.unified_customers` view), then runs the BI snapshot SQL to refresh `bi.unified_customer_360_snapshot`.
- **Order in a run:** AutoCare sync (if requested) → Stripe sync (customers, subscriptions) → **unified.customers** → **bi.unified_customer_360_snapshot**.

## SQL source

- **Repo (canonical):** `sql/create_bi_customer_360_snapshot.sql`
- **Cloud Function (bundled):** `cloud-function/sql/create_bi_customer_360_snapshot.sql`  
  The function substitutes `PROJECT_ID` at runtime when running this SQL.

## GCP setup

- Create the `bi` dataset (e.g. via `gcp-setup/create-tables.sh`).
- The **table** is created and replaced by the Cloud Function; no need to run the BI SQL manually for normal operation.

## Using in BI tools

Point your BI tool at:

- **Project:** your GCP project  
- **Dataset:** `bi`  
- **Table:** `unified_customer_360_snapshot`

Filter/slice by `customer_id`, `email`, `customer_status`, `current_tier_key`, `customer_since`, etc., as needed.
