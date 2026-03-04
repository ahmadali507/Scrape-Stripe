#!/bin/bash
# Set up Cloud Scheduler: one job that triggers the Cloud Function.
# The function runs AutoCare (stripe-customers) + Stripe incremental + unified/BI.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "Cloud Scheduler Setup"
echo "=========================================="
echo ""

PROJECT_ID=$(gcloud config get-value project)
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}Error: No GCP project selected${NC}"
    exit 1
fi
echo -e "${YELLOW}Project: $PROJECT_ID${NC}"
echo ""

REGION="us-central1"
FUNCTION_NAME="stripe-bigquery-sync"
SCHEDULER_JOB="stripe-bigquery-daily-sync"
SCHEDULE="0 4 * * *"   # 4:00 AM UTC daily

FUNCTION_URL=$(gcloud functions describe "$FUNCTION_NAME" \
    --region="$REGION" --gen2 --project="$PROJECT_ID" \
    --format='value(serviceConfig.uri)' 2>/dev/null || echo "")

if [ -z "$FUNCTION_URL" ]; then
    echo -e "${RED}Cloud Function not deployed. Run: ./deploy-function.sh${NC}"
    exit 1
fi

echo -e "${YELLOW}Configuring single scheduler: $SCHEDULER_JOB → Cloud Function${NC}"
echo "  URL: $FUNCTION_URL"
echo "  Schedule: $SCHEDULE UTC"
echo "  (Function runs AutoCare stripe-customers + Stripe + unified/BI; no request body needed)"
echo ""

ARGS=(
    --location="$REGION"
    --schedule="$SCHEDULE"
    --uri="$FUNCTION_URL"
    --http-method=POST
    --time-zone="UTC"
    --attempt-deadline="540s"
    --max-retry-attempts=3
    --max-backoff=3600s
    --min-backoff=60s
    --description="Daily sync: AutoCare (stripe-customers) + Stripe + unified/BI at 4 AM UTC"
)

if gcloud scheduler jobs describe "$SCHEDULER_JOB" \
       --location="$REGION" --project="$PROJECT_ID" &>/dev/null; then
    echo "  Updating existing job..."
    gcloud scheduler jobs update http "$SCHEDULER_JOB" \
        "${ARGS[@]}" --project="$PROJECT_ID"
else
    echo "  Creating job..."
    gcloud scheduler jobs create http "$SCHEDULER_JOB" \
        "${ARGS[@]}" --project="$PROJECT_ID"
fi

echo -e "${GREEN}✓ Scheduler configured${NC}"
echo ""
echo -e "${GREEN}=========================================="
echo "Cloud Scheduler Setup Complete!"
echo "==========================================${NC}"
echo ""
echo "  Job: $SCHEDULER_JOB"
echo "  Schedule: $SCHEDULE UTC"
echo "  Target: Cloud Function ($FUNCTION_NAME) — full sync (AutoCare + Stripe + unified/BI)"
echo ""
echo "Manual trigger:"
echo "  gcloud scheduler jobs run $SCHEDULER_JOB --location=$REGION"
echo ""
echo "View jobs:"
echo "  gcloud scheduler jobs list --location=$REGION"
echo ""
