#!/bin/bash
# Script to deploy the Cloud Function to GCP

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo -e "${RED}Error: Cloud Function source directory not found: $SOURCE_DIR${NC}"
    exit 1
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
echo "Test the function manually:"
echo "  curl -X POST $FUNCTION_URL"
echo ""
echo "Or trigger via gcloud:"
echo "  gcloud functions call $FUNCTION_NAME --region=$REGION --gen2"
echo ""
echo "Next steps:"
echo "  Set up Cloud Scheduler: ./setup-scheduler.sh"
echo ""

