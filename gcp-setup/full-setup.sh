#!/bin/bash
# Complete end-to-end setup script for Stripe to BigQuery Pipeline
# This script runs all setup steps in sequence

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║   Stripe to BigQuery Pipeline - Complete Setup            ║"
echo "║   This will set up everything needed for automated sync   ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Ensure all scripts in this directory are executable (fixes Permission denied when cloning)
chmod +x *.sh 2>/dev/null || true

# Check if we're in GCP Cloud Shell
if [ -z "$GOOGLE_CLOUD_PROJECT" ] && [ -z "$(gcloud config get-value project 2>/dev/null)" ]; then
    echo -e "${RED}Warning: Not in Google Cloud Shell or no project selected${NC}"
    echo "Please run: gcloud config set project YOUR_PROJECT_ID"
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo -e "${BLUE}This script will:${NC}"
echo "  1. Enable GCP APIs"
echo "  2. Create service account"
echo "  3. Create BigQuery datasets"
echo "  4. Store Stripe API key in Secret Manager"
echo "  5. Create BigQuery tables"
echo "  6. Deploy Cloud Function"
echo "  7. Set up Cloud Scheduler"
echo "  8. Test the pipeline"
echo ""

read -p "Ready to begin? (Y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "Setup cancelled."
    exit 0
fi

echo ""

# Step 1: Main setup
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}STEP 1/8: Running main GCP setup${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
./setup.sh
echo ""

# Step 2: Secret Manager
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}STEP 2/8: Setting up Secret Manager${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
./setup-secrets.sh
echo ""

# Step 3: Create tables
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}STEP 3/8: Creating BigQuery tables${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
./create-tables.sh
echo ""

# Step 4: Deploy function
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}STEP 4/8: Deploying Cloud Function${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
./deploy-function.sh
echo ""

# Step 5: Setup scheduler
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}STEP 5/8: Configuring Cloud Scheduler${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
./setup-scheduler.sh
echo ""

# Step 6: Test pipeline
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}STEP 6/8: Testing pipeline${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
./test-pipeline.sh
echo ""

# Final summary
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    🎉 SETUP COMPLETE! 🎉                   ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Your Stripe to BigQuery pipeline is now running!${NC}"
echo ""
echo -e "${BLUE}What's happening now:${NC}"
echo "  ✅ Cloud Function deployed and tested"
echo "  ✅ Daily sync scheduled for 6:00 AM UTC"
echo "  ✅ BigQuery tables ready for queries"
echo "  ✅ Stripe data syncing automatically"
echo ""

PROJECT_ID=$(gcloud config get-value project)

echo -e "${BLUE}Quick commands:${NC}"
echo ""
echo "  View data:"
echo "    bq query --use_legacy_sql=false 'SELECT * FROM \`${PROJECT_ID}.stripe_processed.customers\` LIMIT 10'"
echo ""
echo "  Trigger manual sync:"
echo "    gcloud scheduler jobs run stripe-bigquery-daily-sync --location=us-central1"
echo ""
echo "  View logs:"
echo "    gcloud functions logs read stripe-bigquery-sync --region=us-central1 --gen2 --limit=50"
echo ""
echo "  Check sync status:"
echo "    bq query --use_legacy_sql=false 'SELECT * FROM \`${PROJECT_ID}.stripe_metadata.sync_history\` ORDER BY sync_completed_at DESC LIMIT 5'"
echo ""

echo -e "${BLUE}Next steps:${NC}"
echo "  1. Connect to Data Studio for dashboards"
echo "  2. Set up alerts for failed syncs"
echo "  3. Explore example queries in sql/example_queries.sql"
echo "  4. Customize sync schedule if needed"
echo ""

echo -e "${GREEN}Documentation:${NC}"
echo "  📖 Quick Start: ../QUICKSTART.md"
echo "  📚 Full Guide: ../DEPLOYMENT_GUIDE.md"
echo "  📊 Example Queries: ../sql/example_queries.sql"
echo ""

echo "Thank you for using the Stripe to BigQuery Pipeline! 🚀"
echo ""

