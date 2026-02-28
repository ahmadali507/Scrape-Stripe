#!/bin/bash
# Complete end-to-end setup script for Stripe to BigQuery Pipeline
# This script runs all setup steps in sequence

set -e

# Replit webhook secret (required for new-customer GHL sync)
# Set this before running: export REPLIT_WEBHOOK_SECRET=your-secret
export REPLIT_WEBHOOK_SECRET="${REPLIT_WEBHOOK_SECRET:-xiomara-big-query-secret}"

# AutoCare credentials: do NOT set defaults here.
# Store them in Secret Manager instead (autocare-api-email / autocare-api-password).
# If set as env vars they will be baked into the Cloud Function and override Secret Manager.
# export AUTOCARE_API_EMAIL="..."
# export AUTOCARE_API_PASSWORD="..."

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

# Step 3b: Create unified_customers view (required before first sync with unified/BI)
echo -e "${YELLOW}Creating unified_customers view...${NC}"
PROJECT_ID=$(gcloud config get-value project)
SQL_DIR="$SCRIPT_DIR/../sql"
if [ -f "$SQL_DIR/create_unified_customer_view.sql" ]; then
    if sed "s/PROJECT_ID/${PROJECT_ID}/g" "$SQL_DIR/create_unified_customer_view.sql" | bq query --use_legacy_sql=false --project_id="$PROJECT_ID"; then
        echo -e "${GREEN}✓ unified_customers view created${NC}"
    else
        echo -e "${YELLOW}⚠ View creation failed or already exists. To create manually:${NC}"
        echo "  1. Replace PROJECT_ID in sql/create_unified_customer_view.sql with $PROJECT_ID"
        echo "  2. bq query --use_legacy_sql=false --project_id=$PROJECT_ID < sql/create_unified_customer_view.sql"
    fi
else
    echo -e "${YELLOW}⚠ create_unified_customer_view.sql not found; create view manually before first sync:${NC}"
    echo "  1. Replace PROJECT_ID in sql/create_unified_customer_view.sql with $PROJECT_ID"
    echo "  2. bq query --use_legacy_sql=false --project_id=$PROJECT_ID < sql/create_unified_customer_view.sql"
fi
echo ""

# Step 3c: Pull latest secret values from Secret Manager → export as env vars
# This guarantees deploy-function.sh always bakes the freshest credentials into
# the Cloud Function config, regardless of what was set (or not set) in the shell.
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}STEP 3c: Loading latest secrets from Secret Manager${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

PROJECT_ID=$(gcloud config get-value project)

_load_secret() {
    local SECRET_NAME="$1"
    local ENV_VAR="$2"
    local VALUE
    VALUE=$(gcloud secrets versions access latest \
        --secret="$SECRET_NAME" \
        --project="$PROJECT_ID" 2>/dev/null || echo "")
    if [ -n "$VALUE" ]; then
        export "$ENV_VAR"="$VALUE"
        echo -e "${GREEN}  ✓ $SECRET_NAME → \$$ENV_VAR${NC}"
    else
        echo -e "${YELLOW}  ⚠ $SECRET_NAME not found or empty in Secret Manager — skipping \$$ENV_VAR${NC}"
    fi
}

_load_secret "autocare-api-email"      AUTOCARE_API_EMAIL
_load_secret "autocare-api-password"   AUTOCARE_API_PASSWORD
_load_secret "replit-webhook-url"      REPLIT_WEBHOOK_URL
_load_secret "replit-webhook-secret"   REPLIT_WEBHOOK_SECRET

echo ""
echo -e "${BLUE}  Resolved env vars for deployment:${NC}"
[ -n "$AUTOCARE_API_EMAIL" ]    && echo "    AUTOCARE_API_EMAIL    = (set)" || echo "    AUTOCARE_API_EMAIL    = (not set — AutoCare sync will be skipped)"
[ -n "$AUTOCARE_API_PASSWORD" ] && echo "    AUTOCARE_API_PASSWORD = (set)" || echo "    AUTOCARE_API_PASSWORD = (not set — AutoCare sync will be skipped)"
[ -n "$REPLIT_WEBHOOK_URL" ]    && echo "    REPLIT_WEBHOOK_URL    = $REPLIT_WEBHOOK_URL" || echo "    REPLIT_WEBHOOK_URL    = (not set)"
[ -n "$REPLIT_WEBHOOK_SECRET" ] && echo "    REPLIT_WEBHOOK_SECRET = (set)" || echo "    REPLIT_WEBHOOK_SECRET = (not set)"
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

