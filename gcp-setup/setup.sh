#!/bin/bash
# Stripe to BigQuery Pipeline - GCP Setup Script
# Run this script in Google Cloud Shell

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Stripe to BigQuery Pipeline Setup"
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

# Step 2: Enable required APIs
echo -e "${YELLOW}Step 2: Enabling required GCP APIs${NC}"
echo "This may take a few minutes..."

gcloud services enable bigquery.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudscheduler.googleapis.com \
  secretmanager.googleapis.com \
  cloudbuild.googleapis.com \
  cloudresourcemanager.googleapis.com

echo -e "${GREEN}✓ APIs enabled successfully${NC}"
echo ""

# Step 3: Create service account
echo -e "${YELLOW}Step 3: Creating service account${NC}"
SERVICE_ACCOUNT_NAME="stripe-sync-sa"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Check if service account already exists
if gcloud iam service-accounts describe $SERVICE_ACCOUNT_EMAIL &>/dev/null; then
    echo -e "${YELLOW}Service account already exists: $SERVICE_ACCOUNT_EMAIL${NC}"
else
    gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME \
        --display-name="Stripe BigQuery Sync Service Account" \
        --description="Service account for automated Stripe to BigQuery data sync"
    echo -e "${GREEN}✓ Service account created: $SERVICE_ACCOUNT_EMAIL${NC}"
fi
echo ""

# Step 4: Grant IAM roles to service account
echo -e "${YELLOW}Step 4: Assigning IAM roles to service account${NC}"

# BigQuery Data Editor role
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
    --role="roles/bigquery.dataEditor" \
    --condition=None

# BigQuery Job User role (to run queries)
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
    --role="roles/bigquery.jobUser" \
    --condition=None

# Secret Manager Secret Accessor role
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
    --role="roles/secretmanager.secretAccessor" \
    --condition=None

echo -e "${GREEN}✓ IAM roles assigned${NC}"
echo ""

# Step 5: Create BigQuery datasets (skip if already exist)
echo -e "${YELLOW}Step 5: Creating BigQuery datasets${NC}"

# Create stripe_raw dataset
if bq show "${PROJECT_ID}:stripe_raw" &>/dev/null; then
    echo -e "${GREEN}✓ Dataset stripe_raw already exists (skipped)${NC}"
else
    bq mk --dataset \
        --location=US \
        --description="Raw JSON data from Stripe API" \
        "${PROJECT_ID}:stripe_raw"
    echo -e "${GREEN}✓ Created dataset: stripe_raw${NC}"
fi

# Create stripe_processed dataset
if bq show "${PROJECT_ID}:stripe_processed" &>/dev/null; then
    echo -e "${GREEN}✓ Dataset stripe_processed already exists (skipped)${NC}"
else
    bq mk --dataset \
        --location=US \
        --description="Processed and flattened Stripe data" \
        "${PROJECT_ID}:stripe_processed"
    echo -e "${GREEN}✓ Created dataset: stripe_processed${NC}"
fi

# Create stripe_metadata dataset
if bq show "${PROJECT_ID}:stripe_metadata" &>/dev/null; then
    echo -e "${GREEN}✓ Dataset stripe_metadata already exists (skipped)${NC}"
else
    bq mk --dataset \
        --location=US \
        --description="Metadata and sync tracking for Stripe pipeline" \
        "${PROJECT_ID}:stripe_metadata"
    echo -e "${GREEN}✓ Created dataset: stripe_metadata${NC}"
fi

echo ""
echo -e "${GREEN}=========================================="
echo -e "Setup Complete!"
echo -e "==========================================${NC}"
echo ""
echo "Service Account: $SERVICE_ACCOUNT_EMAIL"
echo "BigQuery Datasets Created:"
echo "  - stripe_raw"
echo "  - stripe_processed"
echo "  - stripe_metadata"
echo ""
echo "Next steps:"
echo "1. Store your Stripe API key in Secret Manager:"
echo "   ./setup-secrets.sh"
echo "2. Create BigQuery tables:"
echo "   ./create-tables.sh"
echo "3. Deploy the Cloud Function"
echo ""

