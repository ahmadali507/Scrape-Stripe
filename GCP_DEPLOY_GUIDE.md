# Step-by-step: Deploy / update the project on GCP

This guide covers **updating your existing** Stripe → BigQuery pipeline and **adding** the Replit/GoHighLevel webhook. Use it when you already have the scheduler and Cloud Function deployed and want to update them with the latest code and Replit integration.

---

## What you already have (existing)

- **Cloud Scheduler** job: `stripe-bigquery-daily-sync` (e.g. daily at 6:00 AM UTC)
- **Cloud Function**: `stripe-bigquery-sync` (Stripe → BigQuery)
- **BigQuery**: datasets and tables for customers/subscriptions

## What we’re doing

1. **Update** the Cloud Function with the new code (Replit webhook, mandatory GHL send).
2. **Set** the Replit webhook URL and secret on the function.
3. **Re-point** the scheduler to the (possibly new) function URL if needed.
4. **Test** the full flow.

---

## Prerequisites

- **Google Cloud SDK** (`gcloud`) installed and logged in.
- **GCP project** where the function and scheduler already exist.
- **Replit webhook secret** (e.g. from `secret.md`): `xiomara-big-query-secret`.

---

## Step 1: Set your GCP project

From a terminal (Cloud Shell or local):

```bash
# Set the project (use your actual project ID)
gcloud config set project YOUR_PROJECT_ID

# Confirm
gcloud config get-value project
```

---

## Step 2: Go to the project folder

Use the repo root (where `cloud-function/` and `gcp-setup/` live):

```bash
cd /path/to/Scrape-Stripe
# Example on Windows:  cd d:\projects\upwork\Samuel\Scrape-Stripe
```

---

## Step 3: (Optional) Verify existing resources

Only if you want to double-check before updating.

**BigQuery datasets**

```bash
bq ls --project_id=YOUR_PROJECT_ID
# You should see: stripe_raw, stripe_processed, stripe_metadata
```

**Stripe secret**

```bash
gcloud secrets describe stripe-api-key --project=YOUR_PROJECT_ID
# If this fails, run:  ./gcp-setup/setup-secrets.sh
```

**Current function**

```bash
gcloud functions describe stripe-bigquery-sync --region=us-central1 --gen2 --format="yaml(serviceConfig.uri,state)"
# Confirms the function exists and shows its URL.
```

---

## Step 4: Store Replit webhook URL and secret in GCP Secret Manager

Store the Replit webhook URL and secret in Secret Manager so the Cloud Function can read them at runtime (no need to pass them as env vars at deploy time).

Replace `YOUR_PROJECT_ID` with your GCP project ID. Use your actual webhook URL and secret value.

### 4.1 Create the secret for the webhook URL

```bash
# Create the secret (one-time)
gcloud secrets create replit-webhook-url \
  --project=hitech-484412 \
  --replication-policy="automatic" \
  --labels="purpose=replit-ghl"

# Add the URL as the first version (paste your URL after the echo)
echo -n "https://data-whisperer--samuel447.replit.app/api/webhooks/new-customers" | \
  gcloud secrets versions add replit-webhook-url --data-file=- --project=hitech-484412
```

### 4.2 Create the secret for the webhook secret

```bash
# Create the secret (one-time)
gcloud secrets create replit-webhook-secret \
  --project=hitech-484412 \
  --replication-policy="automatic" \
  --labels="purpose=replit-ghl"

# Add the secret value (replace with your actual webhook secret, e.g. xiomara-big-query-secret)
echo -n "xiomara-big-query-secret" | \
  gcloud secrets versions add replit-webhook-secret --data-file=- --project=hitech-484412
```



### 4.3 Grant the Cloud Function service account access to both secrets

The function runs as `stripe-sync-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com`. It needs permission to read the new secrets.

```bash
PROJECT_ID=YOUR_PROJECT_ID
SA_EMAIL="stripe-sync-sa@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud secrets add-iam-policy-binding replit-webhook-url \
  --project=$PROJECT_ID \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/secretmanager.secretAccessor"

gcloud secrets add-iam-policy-binding replit-webhook-secret \
  --project=$PROJECT_ID \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/secretmanager.secretAccessor"
```

### 4.4 Verify

```bash
# List secrets (you should see replit-webhook-url and replit-webhook-secret)
gcloud secrets list  --filter="name:replit"

# Test read (optional; requires your user to have access)
gcloud secrets versions access latest --secret=replit-webhook-url 
gcloud secrets versions access latest --secret=replit-webhook-secret 
```

After this, the Cloud Function will read **Replit webhook URL** and **Replit webhook secret** from Secret Manager at runtime. You do **not** need to set `REPLIT_WEBHOOK_URL` or `REPLIT_WEBHOOK_SECRET` as environment variables when deploying.

---

## Step 5: Update and deploy the Cloud Function

This deploys the **latest code** (including Replit client, mandatory GHL send, and Secret Manager support for Replit config).

```bash
cd gcp-setup
chmod +x deploy-function.sh
./deploy-function.sh
```

**What this does:**

- Builds and deploys the function from `../cloud-function`.
- Sets env var: `GOOGLE_CLOUD_PROJECT` (required for BigQuery and Secret Manager).
- If you set `REPLIT_WEBHOOK_URL` and `REPLIT_WEBHOOK_SECRET` in the environment, they are passed as env vars (and override Secret Manager). If you **did Step 4**, you can leave them unset and the function will read URL and secret from Secret Manager.

**When using Secret Manager (Step 4):** You do **not** need to export `REPLIT_WEBHOOK_SECRET` before deploying. The script may warn about missing secret; you can ignore it as long as the two secrets exist in GCP and the service account has access.

---

## Step 6: Update / verify Cloud Scheduler

The scheduler job must call the **current** Cloud Function URL. After a deploy, the URL usually stays the same; updating the job ensures it uses the latest URL.

```bash
# Still in gcp-setup
./setup-scheduler.sh
```

**What this does:**

- Resolves the **current** URL of `stripe-bigquery-sync` (Gen2).
- Creates or **updates** the HTTP job `stripe-bigquery-daily-sync` to POST to that URL on schedule (e.g. `0 6 * * *` = 6:00 AM UTC).

No need to create a new job; the script updates the existing one.

---

## Step 7: Test the pipeline

**7.1 Trigger the function once**

```bash
# Get the function URL
FUNCTION_URL=$(gcloud functions describe stripe-bigquery-sync --region=us-central1 --gen2 --format='value(serviceConfig.uri)')

# Trigger sync (no body = sync customers + subscriptions)
curl -X POST "$FUNCTION_URL" -H "Content-Type: application/json"
```

**7.2 Check the response**

- HTTP **200** and JSON with `"success": true` and per-entity `results` → sync (and, if there were new customers, Replit send) succeeded.
- HTTP **500** or `"success": false` → check `results.customers.error` or `results.subscriptions.error` and logs.

**7.3 Check logs**

```bash
gcloud functions logs read stripe-bigquery-sync --region=us-central1 --gen2 --limit=80
```

Look for:

- “New customers sent to GHL webhook” (if there were new customers).
- Any “GoHighLevel webhook not configured or send failed” (fix env vars and redeploy).

**7.4 (Optional) Trigger via scheduler**

```bash
gcloud scheduler jobs run stripe-bigquery-daily-sync --location=us-central1
```

Then check logs and BigQuery again.

**7.5 Check BigQuery**

```bash
PROJECT_ID=$(gcloud config get-value project)
bq query --use_legacy_sql=false "SELECT entity_type, records_synced, status, sync_completed_at FROM \`${PROJECT_ID}.stripe_metadata.sync_history\` ORDER BY sync_completed_at DESC LIMIT 5"
```

---

## Step 8: Summary checklist

| Step | Action | Command / note |
|------|--------|----------------|
| 1 | Set GCP project | `gcloud config set project YOUR_PROJECT_ID` |
| 2 | Open project folder | `cd /path/to/Scrape-Stripe` |
| 3 | (Optional) Verify | BigQuery datasets, `stripe-api-key` secret, function exists |
| 4 | Store Replit in Secret Manager | Create `replit-webhook-url` and `replit-webhook-secret`, grant SA access (see Step 4 above) |
| 5 | Deploy function | `cd gcp-setup && ./deploy-function.sh` |
| 6 | Update scheduler | `./setup-scheduler.sh` |
| 7 | Test | `curl -X POST $FUNCTION_URL` then check logs and BigQuery |

---

## Quick copy-paste sequence (with Secret Manager)

Run these after replacing `YOUR_PROJECT_ID` with your project ID.

**Create Replit secrets and grant access:**

```bash
gcloud config set project YOUR_PROJECT_ID

# Create replit-webhook-url and add version
gcloud secrets create replit-webhook-url --project=YOUR_PROJECT_ID --replication-policy="automatic" 2>/dev/null || true
echo -n "https://data-whisperer--samuel447.replit.app/api/webhooks/new-customers" | gcloud secrets versions add replit-webhook-url --data-file=- --project=YOUR_PROJECT_ID

# Create replit-webhook-secret and add version (replace with your actual secret if different)
gcloud secrets create replit-webhook-secret --project=YOUR_PROJECT_ID --replication-policy="automatic" 2>/dev/null || true
echo -n "xiomara-big-query-secret" | gcloud secrets versions add replit-webhook-secret --data-file=- --project=YOUR_PROJECT_ID

# Grant Cloud Function service account access
PROJECT_ID=YOUR_PROJECT_ID
SA_EMAIL="stripe-sync-sa@${PROJECT_ID}.iam.gserviceaccount.com"
gcloud secrets add-iam-policy-binding replit-webhook-url --project=$PROJECT_ID --member="serviceAccount:${SA_EMAIL}" --role="roles/secretmanager.secretAccessor"
gcloud secrets add-iam-policy-binding replit-webhook-secret --project=$PROJECT_ID --member="serviceAccount:${SA_EMAIL}" --role="roles/secretmanager.secretAccessor"
```

**Deploy function and scheduler:**

```bash
cd gcp-setup
./deploy-function.sh
./setup-scheduler.sh
```

**Test:**

```bash
curl -X POST $(gcloud functions describe stripe-bigquery-sync --region=us-central1 --gen2 --format='value(serviceConfig.uri)')
```

---

## If something fails

**Function deploy fails (permissions)**

- Ensure the account running `gcloud` can deploy Cloud Functions and use the service account.
- Re-run IAM setup if needed: `./gcp-setup/setup.sh` (then secrets and tables as needed).

**“GoHighLevel webhook not configured or send failed”**

- If using **Secret Manager**: ensure secrets `replit-webhook-url` and `replit-webhook-secret` exist and the service account `stripe-sync-sa@PROJECT_ID.iam.gserviceaccount.com` has `roles/secretmanager.secretAccessor` on both.
- If using **env vars**: confirm they are set on the function:
  ```bash
  gcloud functions describe stripe-bigquery-sync --region=us-central1 --gen2 --format="yaml(serviceConfig.environmentVariables)"
  ```
  You should see `REPLIT_WEBHOOK_URL` and `REPLIT_WEBHOOK_SECRET` when set.
- The function reads URL/secret from env first, then Secret Manager. Fix whichever source you use and redeploy if needed.

**Scheduler not firing**

- Check job: `gcloud scheduler jobs describe stripe-bigquery-daily-sync --location=us-central1`
- Ensure the job’s URL matches the function URL from Step 7.1.
- Run `./setup-scheduler.sh` again to refresh the job.

**Replit returns 401**

- The secret in GCP must match the one configured for the webhook on Replit (`x-webhook-secret` / `Authorization: Bearer`). Use the same value as in your Replit listener (e.g. `xiomara-big-query-secret`).

---

## What gets updated vs created

| Resource | Action |
|----------|--------|
| Cloud Function `stripe-bigquery-sync` | **Updated**: new code + env vars (Replit URL and secret). |
| Scheduler job `stripe-bigquery-daily-sync` | **Updated**: target URL refreshed to current function. |
| BigQuery datasets/tables | **Unchanged** (already exist). |
| Secret `stripe-api-key` | **Unchanged** (already exists). |
| Service account `stripe-sync-sa` | **Unchanged**. |

No new GCP resources are required; this is an update of the existing deployment plus the new Replit webhook configuration.
