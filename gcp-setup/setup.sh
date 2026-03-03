#!/bin/bash
# Stripe + AutoCare to BigQuery Pipeline - GCP Setup Script
# Run this script in Google Cloud Shell

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "Stripe + AutoCare Pipeline Setup"
echo "=========================================="
echo ""

# Step 1: Get project ID
echo -e "${YELLOW}Step 1: Setting up project${NC}"
PROJECT_ID=$(gcloud config get-value project)
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}Error: No GCP project selected${NC}"
    echo "Please run: gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi
echo -e "${GREEN}Using project: $PROJECT_ID${NC}"
echo ""

# Step 2: Enable all required APIs
# Includes Cloud Run + Artifact Registry needed by the AutoCare Cloud Run Job
echo -e "${YELLOW}Step 2: Enabling required GCP APIs${NC}"
echo "This may take a few minutes..."

gcloud services enable \
  bigquery.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudscheduler.googleapis.com \
  secretmanager.googleapis.com \
  cloudbuild.googleapis.com \
  cloudresourcemanager.googleapis.com \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  --project="$PROJECT_ID" --quiet

echo -e "${GREEN}✓ APIs enabled successfully${NC}"
echo ""

# Step 3: Create service account
echo -e "${YELLOW}Step 3: Creating service account${NC}"
SERVICE_ACCOUNT_NAME="stripe-sync-sa"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

if gcloud iam service-accounts describe "$SERVICE_ACCOUNT_EMAIL" \
       --project="$PROJECT_ID" &>/dev/null; then
    echo -e "${YELLOW}Service account already exists: $SERVICE_ACCOUNT_EMAIL${NC}"
else
    gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
        --display-name="Stripe + AutoCare BigQuery Sync" \
        --description="Service account for Stripe and AutoCare data pipeline" \
        --project="$PROJECT_ID"
    echo -e "${GREEN}✓ Service account created: $SERVICE_ACCOUNT_EMAIL${NC}"
fi
echo ""

# Step 4: Grant IAM roles to service account
echo -e "${YELLOW}Step 4: Assigning IAM roles to service account${NC}"

declare -a ROLES=(
    "roles/bigquery.dataEditor"       # read/write BQ tables
    "roles/bigquery.jobUser"          # run BQ queries (MERGE, CREATE TABLE, etc.)
    "roles/secretmanager.secretAccessor"  # read secrets at runtime
    "roles/run.invoker"               # Cloud Scheduler → invoke Cloud Run Job
    "roles/artifactregistry.writer"   # Cloud Build → push Docker images
)

for ROLE in "${ROLES[@]}"; do
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
        --role="$ROLE" \
        --condition=None \
        --quiet
    echo -e "  ${GREEN}✓${NC} $ROLE"
done

echo -e "${GREEN}✓ IAM roles assigned${NC}"
echo ""

# Step 5: Create all BigQuery datasets
echo -e "${YELLOW}Step 5: Creating BigQuery datasets${NC}"

declare -A DATASETS=(
    ["stripe_raw"]="Raw JSON data from Stripe API"
    ["stripe_processed"]="Processed and flattened Stripe data"
    ["stripe_metadata"]="Sync history and metadata for Stripe pipeline"
    ["autocare_raw"]="Raw JSON data from AutoCare API"
    ["autocare_processed"]="Processed AutoCare data — customers, sessions, cars, tiers (includes staging tables)"
    ["autocare_metadata"]="Sync history and metadata for AutoCare pipeline"
    ["unified"]="Unified customer view joining AutoCare and Stripe"
    ["bi"]="Flat BI-ready customer 360 snapshot for Looker/Metabase/Power BI"
)

for DS in "${!DATASETS[@]}"; do
    if bq show "${PROJECT_ID}:${DS}" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $DS already exists (skipped)"
    else
        bq mk --dataset \
            --location=US \
            --description="${DATASETS[$DS]}" \
            "${PROJECT_ID}:${DS}"
        echo -e "  ${GREEN}✓${NC} Created dataset: $DS"
    fi
done

echo ""
echo -e "${GREEN}=========================================="
echo -e "Setup Complete!"
echo -e "==========================================${NC}"
echo ""
echo "Service Account : $SERVICE_ACCOUNT_EMAIL"
echo ""
echo -e "${BLUE}BigQuery datasets:${NC}"
for DS in stripe_raw stripe_processed stripe_metadata \
          autocare_raw autocare_processed autocare_metadata \
          unified bi; do
    echo "  ✓ $DS"
done
echo ""
echo "Next steps:"
echo "  1. Store secrets in Secret Manager:"
echo "       ./setup-secrets.sh"
echo "  2. Create BigQuery tables (includes staging tables):"
echo "       ./create-tables.sh"
echo "  3. Deploy Stripe Cloud Function:"
echo "       ./deploy-function.sh"
echo "  4. Deploy AutoCare Cloud Run Job (builds Docker image, ~5 min):"
echo "       ./deploy-job.sh"
echo "  5. Configure Cloud Scheduler:"
echo "       ./setup-scheduler.sh"
echo ""

