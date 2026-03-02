#!/bin/bash
# Script to deploy the Cloud Function to GCP

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "Deploy Stripe to BigQuery Cloud Function"
echo "=========================================="
echo ""

PROJECT_ID=$(gcloud config get-value project)

if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}Error: No GCP project selected${NC}"
    exit 1
fi

echo -e "${YELLOW}Project: $PROJECT_ID${NC}"
echo ""

# ── Load latest secrets from Secret Manager ──────────────────────────────────
# Always pulls the newest version of every secret so the deployed function
# is guaranteed to use current credentials, not stale env vars.
echo -e "${YELLOW}Loading latest secrets from Secret Manager...${NC}"

_load_secret() {
    local SECRET_NAME="$1"
    local ENV_VAR="$2"
    local VALUE
    VALUE=$(gcloud secrets versions access latest \
        --secret="$SECRET_NAME" \
        --project="$PROJECT_ID" 2>/dev/null || echo "")
    if [ -n "$VALUE" ]; then
        export "$ENV_VAR"="$VALUE"
        echo -e "${GREEN}  ✓ $SECRET_NAME loaded into \$$ENV_VAR${NC}"
    else
        echo -e "${YELLOW}  ⚠ $SECRET_NAME not found or empty — \$$ENV_VAR will not be set${NC}"
    fi
}

_mask() {
    # Show first 4 chars + *** for verification without fully exposing the value
    local V="$1"
    if [ ${#V} -le 4 ]; then echo "****"; else echo "${V:0:4}****"; fi
}

_load_secret "autocare-api-email"    AUTOCARE_API_EMAIL
_load_secret "autocare-api-password" AUTOCARE_API_PASSWORD
_load_secret "replit-webhook-url"    REPLIT_WEBHOOK_URL
_load_secret "replit-webhook-secret" REPLIT_WEBHOOK_SECRET

echo ""
echo -e "${BLUE}━━━━ Credentials resolved for this deployment ━━━━━━━━━━━━━━━━${NC}"
echo -e "  AUTOCARE_API_EMAIL    = ${AUTOCARE_API_EMAIL:-(NOT SET — AutoCare sync will fail)}"
if [ -n "$AUTOCARE_API_PASSWORD" ]; then
    echo -e "  AUTOCARE_API_PASSWORD = $(_mask "$AUTOCARE_API_PASSWORD") (masked)"
else
    echo -e "  AUTOCARE_API_PASSWORD = ${RED}(NOT SET — AutoCare sync will fail)${NC}"
fi
echo -e "  REPLIT_WEBHOOK_URL    = ${REPLIT_WEBHOOK_URL:-(not set)}"
if [ -n "$REPLIT_WEBHOOK_SECRET" ]; then
    echo -e "  REPLIT_WEBHOOK_SECRET = $(_mask "$REPLIT_WEBHOOK_SECRET") (masked)"
else
    echo -e "  REPLIT_WEBHOOK_SECRET = (not set)"
fi
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Configuration
FUNCTION_NAME="stripe-bigquery-sync"
REGION="us-central1"
RUNTIME="python311"
ENTRY_POINT="sync_handler"
SERVICE_ACCOUNT="stripe-sync-sa@${PROJECT_ID}.iam.gserviceaccount.com"
MEMORY="2GB"
TIMEOUT="540s"

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SOURCE_DIR="$SCRIPT_DIR/../cloud-function"
SQL_DIR="$SCRIPT_DIR/../sql"

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo -e "${RED}Error: Cloud Function source directory not found: $SOURCE_DIR${NC}"
    exit 1
fi

# Copy BI snapshot SQL from single source (sql/) into cloud-function/sql/ for deployment
mkdir -p "$SOURCE_DIR/sql"
if [ -f "$SQL_DIR/create_bi_customer_360_snapshot.sql" ]; then
    cp "$SQL_DIR/create_bi_customer_360_snapshot.sql" "$SOURCE_DIR/sql/"
    echo -e "${GREEN}✓ BI snapshot SQL copied to cloud-function/sql/${NC}"
fi

echo -e "${YELLOW}Deploying Cloud Function...${NC}"
echo "  Name: $FUNCTION_NAME"
echo "  Region: $REGION"
echo "  Runtime: $RUNTIME"
echo "  Service Account: $SERVICE_ACCOUNT"
echo "  Memory: $MEMORY"
echo "  Timeout: $TIMEOUT"
echo ""

# Replit/GoHighLevel webhook (mandatory for new-customer sync)
REPLIT_WEBHOOK_URL_DEFAULT="https://data-whisperer--samuel447.replit.app/api/webhooks/new-customers"
REPLIT_URL="${REPLIT_WEBHOOK_URL:-$REPLIT_WEBHOOK_URL_DEFAULT}"
REPLIT_SECRET="${REPLIT_WEBHOOK_SECRET:-}"
if [ -z "$REPLIT_SECRET" ]; then
    echo -e "${YELLOW}Warning: REPLIT_WEBHOOK_SECRET not set.${NC}"
    echo "  Customer sync will fail when there are new customers until you set it."
    echo "  Run: export REPLIT_WEBHOOK_SECRET=your-webhook-secret"
    echo "  Then re-run this script."
    echo ""
fi

ENV_VARS="GOOGLE_CLOUD_PROJECT=$PROJECT_ID"
[ -n "$REPLIT_URL" ] && [ -n "$REPLIT_SECRET" ] && ENV_VARS="$ENV_VARS,REPLIT_WEBHOOK_URL=$REPLIT_URL,REPLIT_WEBHOOK_SECRET=$REPLIT_SECRET"
# AutoCare API (required to populate autocare_* tables; set before running this script to include them)
[ -n "$AUTOCARE_API_EMAIL" ] && [ -n "$AUTOCARE_API_PASSWORD" ] && ENV_VARS="$ENV_VARS,AUTOCARE_API_EMAIL=$AUTOCARE_API_EMAIL,AUTOCARE_API_PASSWORD=$AUTOCARE_API_PASSWORD"

# Deploy the function
gcloud functions deploy $FUNCTION_NAME \
    --gen2 \
    --runtime=$RUNTIME \
    --region=$REGION \
    --source=$SOURCE_DIR \
    --entry-point=$ENTRY_POINT \
    --trigger-http \
    --allow-unauthenticated \
    --service-account=$SERVICE_ACCOUNT \
    --memory=$MEMORY \
    --timeout=$TIMEOUT \
    --set-env-vars "$ENV_VARS"

echo ""
echo -e "${GREEN}=========================================="
echo "Cloud Function Deployed Successfully!"
echo "==========================================${NC}"
echo ""

# Get function URL
FUNCTION_URL=$(gcloud functions describe $FUNCTION_NAME \
    --region=$REGION \
    --gen2 \
    --format='value(serviceConfig.uri)')

echo "Function URL: $FUNCTION_URL"
echo ""
echo "Test the function manually (each run syncs Stripe + AutoCare):"
echo "  curl -X POST $FUNCTION_URL -H 'Content-Type: application/json'"
echo ""
echo "Or trigger via gcloud:"
echo "  gcloud functions call $FUNCTION_NAME --region=$REGION --gen2"
echo ""
echo "AutoCare credentials (env or Secret Manager autocare-api-email / autocare-api-password) required for AutoCare data."
echo ""
echo "Next steps:"
echo "  Set up Cloud Scheduler: ./setup-scheduler.sh"
echo ""

