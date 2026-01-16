#!/bin/bash
# Cleanup script - Remove existing Stripe BigQuery setup

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "Cleanup Existing Stripe Setup"
echo "=========================================="
echo ""

PROJECT_ID=$(gcloud config get-value project)

if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}Error: No GCP project selected${NC}"
    exit 1
fi

echo -e "${YELLOW}Project: $PROJECT_ID${NC}"
echo ""
echo -e "${RED}WARNING: This will delete:${NC}"
echo "  - Cloud Scheduler job"
echo "  - Cloud Function"
echo "  - All BigQuery tables (data will be lost!)"
echo "  - BigQuery datasets"
echo ""
read -p "Are you sure you want to continue? Type 'yes' to confirm: " -r
echo

if [ "$REPLY" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""

# 1. Delete Cloud Scheduler
echo -e "${YELLOW}Step 1: Deleting Cloud Scheduler...${NC}"
if gcloud scheduler jobs describe stripe-bigquery-daily-sync --location=us-central1 &>/dev/null; then
    gcloud scheduler jobs delete stripe-bigquery-daily-sync \
        --location=us-central1 \
        --quiet
    echo -e "${GREEN}✓ Scheduler deleted${NC}"
else
    echo -e "${YELLOW}Scheduler not found, skipping${NC}"
fi
echo ""

# 2. Delete Cloud Function
echo -e "${YELLOW}Step 2: Deleting Cloud Function...${NC}"
if gcloud functions describe stripe-bigquery-sync --region=us-central1 --gen2 &>/dev/null; then
    gcloud functions delete stripe-bigquery-sync \
        --region=us-central1 \
        --gen2 \
        --quiet
    echo -e "${GREEN}✓ Cloud Function deleted${NC}"
else
    echo -e "${YELLOW}Cloud Function not found, skipping${NC}"
fi
echo ""

# 3. Delete BigQuery datasets (this deletes all tables inside)
echo -e "${YELLOW}Step 3: Deleting BigQuery datasets...${NC}"

if bq ls -d $PROJECT_ID:stripe_raw &>/dev/null; then
    bq rm -r -f -d $PROJECT_ID:stripe_raw
    echo -e "${GREEN}✓ Deleted stripe_raw dataset${NC}"
else
    echo -e "${YELLOW}stripe_raw not found, skipping${NC}"
fi

if bq ls -d $PROJECT_ID:stripe_processed &>/dev/null; then
    bq rm -r -f -d $PROJECT_ID:stripe_processed
    echo -e "${GREEN}✓ Deleted stripe_processed dataset${NC}"
else
    echo -e "${YELLOW}stripe_processed not found, skipping${NC}"
fi

if bq ls -d $PROJECT_ID:stripe_metadata &>/dev/null; then
    bq rm -r -f -d $PROJECT_ID:stripe_metadata
    echo -e "${GREEN}✓ Deleted stripe_metadata dataset${NC}"
else
    echo -e "${YELLOW}stripe_metadata not found, skipping${NC}"
fi

echo ""
echo -e "${GREEN}=========================================="
echo "Cleanup Complete!"
echo "==========================================${NC}"
echo ""
echo "Removed:"
echo "  ✓ Cloud Scheduler job"
echo "  ✓ Cloud Function"
echo "  ✓ BigQuery datasets and tables"
echo ""
echo "Kept:"
echo "  • Service account (stripe-sync-sa)"
echo "  • Secret Manager secret (stripe-api-key)"
echo "  • Enabled APIs"
echo ""
echo "Next steps:"
echo "  1. Run: ./setup.sh"
echo "  2. Run: ./create-tables.sh"
echo "  3. Run: ./deploy-function.sh"
echo "  4. Run: ./setup-scheduler.sh"
echo ""

