#!/bin/bash
# Script to set up Cloud Scheduler for daily Stripe sync

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Configuration
JOB_NAME="stripe-bigquery-daily-sync"
SCHEDULE="0 6 * * *"  # 6:00 AM UTC daily
TIME_ZONE="UTC"
REGION="us-central1"
FUNCTION_NAME="stripe-bigquery-sync"

# Get the Cloud Function URL
echo -e "${YELLOW}Getting Cloud Function URL...${NC}"
FUNCTION_URL=$(gcloud functions describe $FUNCTION_NAME \
    --region=$REGION \
    --gen2 \
    --format='value(serviceConfig.uri)')

if [ -z "$FUNCTION_URL" ]; then
    echo -e "${RED}Error: Could not find Cloud Function URL${NC}"
    echo "Make sure the function is deployed first: ./deploy-function.sh"
    exit 1
fi

echo "Function URL: $FUNCTION_URL"
echo ""

# Check if job already exists
if gcloud scheduler jobs describe $JOB_NAME --location=$REGION &>/dev/null; then
    echo -e "${YELLOW}Scheduler job already exists. Updating...${NC}"
    
    gcloud scheduler jobs update http $JOB_NAME \
        --location=$REGION \
        --schedule="$SCHEDULE" \
        --uri="$FUNCTION_URL" \
        --http-method=POST \
        --time-zone="$TIME_ZONE" \
        --attempt-deadline=540s \
        --max-retry-attempts=3 \
        --max-backoff=3600s \
        --min-backoff=60s
    
    echo -e "${GREEN}✓ Scheduler job updated${NC}"
else
    echo -e "${YELLOW}Creating new scheduler job...${NC}"
    
    gcloud scheduler jobs create http $JOB_NAME \
        --location=$REGION \
        --schedule="$SCHEDULE" \
        --uri="$FUNCTION_URL" \
        --http-method=POST \
        --time-zone="$TIME_ZONE" \
        --attempt-deadline=540s \
        --max-retry-attempts=3 \
        --max-backoff=3600s \
        --min-backoff=60s \
        --description="Daily sync of Stripe data to BigQuery at 6:00 AM UTC"
    
    echo -e "${GREEN}✓ Scheduler job created${NC}"
fi

echo ""
echo -e "${GREEN}=========================================="
echo "Cloud Scheduler Setup Complete!"
echo "==========================================${NC}"
echo ""
echo "Job Name: $JOB_NAME"
echo "Schedule: $SCHEDULE ($TIME_ZONE)"
echo "Next Run: 6:00 AM UTC daily"
echo ""
echo "To run the job manually:"
echo "  gcloud scheduler jobs run $JOB_NAME --location=$REGION"
echo ""
echo "To pause the job:"
echo "  gcloud scheduler jobs pause $JOB_NAME --location=$REGION"
echo ""
echo "To resume the job:"
echo "  gcloud scheduler jobs resume $JOB_NAME --location=$REGION"
echo ""
echo "To view job details:"
echo "  gcloud scheduler jobs describe $JOB_NAME --location=$REGION"
echo ""

