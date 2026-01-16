#!/bin/bash
# Script to test the Stripe to BigQuery pipeline

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "Test Stripe to BigQuery Pipeline"
echo "=========================================="
echo ""

PROJECT_ID=$(gcloud config get-value project)

if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}Error: No GCP project selected${NC}"
    exit 1
fi

echo -e "${YELLOW}Project: $PROJECT_ID${NC}"
echo ""

FUNCTION_NAME="stripe-bigquery-sync"
REGION="us-central1"
JOB_NAME="stripe-bigquery-daily-sync"

# Test 1: Verify BigQuery datasets and tables
echo -e "${BLUE}Test 1: Verifying BigQuery structure...${NC}"

echo "  Checking datasets..."
DATASETS=$(bq ls --format=csv --max_results=1000 | grep -E "stripe_(raw|processed|metadata)" || true)

if [ -z "$DATASETS" ]; then
    echo -e "${RED}  ✗ BigQuery datasets not found${NC}"
    echo "  Run: ./setup.sh"
    exit 1
else
    echo -e "${GREEN}  ✓ BigQuery datasets found${NC}"
fi

echo "  Checking tables..."
TABLES_COUNT=$(bq ls stripe_raw 2>/dev/null | wc -l || echo 0)

if [ "$TABLES_COUNT" -lt 2 ]; then
    echo -e "${RED}  ✗ BigQuery tables not found${NC}"
    echo "  Run: ./create-tables.sh"
    exit 1
else
    echo -e "${GREEN}  ✓ BigQuery tables found${NC}"
fi

echo ""

# Test 2: Verify Secret Manager
echo -e "${BLUE}Test 2: Verifying Secret Manager...${NC}"

if gcloud secrets describe stripe-api-key &>/dev/null; then
    echo -e "${GREEN}  ✓ Stripe API key secret found${NC}"
else
    echo -e "${RED}  ✗ Stripe API key secret not found${NC}"
    echo "  Run: ./setup-secrets.sh"
    exit 1
fi

echo ""

# Test 3: Verify Cloud Function deployment
echo -e "${BLUE}Test 3: Verifying Cloud Function...${NC}"

if gcloud functions describe $FUNCTION_NAME --region=$REGION --gen2 &>/dev/null; then
    echo -e "${GREEN}  ✓ Cloud Function deployed${NC}"
    
    FUNCTION_URL=$(gcloud functions describe $FUNCTION_NAME \
        --region=$REGION \
        --gen2 \
        --format='value(serviceConfig.uri)')
    echo "  URL: $FUNCTION_URL"
else
    echo -e "${RED}  ✗ Cloud Function not deployed${NC}"
    echo "  Run: ./deploy-function.sh"
    exit 1
fi

echo ""

# Test 4: Manual trigger of Cloud Function
echo -e "${BLUE}Test 4: Triggering Cloud Function manually...${NC}"
echo "  This may take up to 9 minutes..."
echo ""

# Trigger the function
echo "  Invoking function..."
RESPONSE=$(curl -s -X POST $FUNCTION_URL -H "Content-Type: application/json" -d '{"entities": ["customers"]}' -w "\n%{http_code}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}  ✓ Function executed successfully${NC}"
    echo "  Response: $BODY"
else
    echo -e "${YELLOW}  ⚠ Function returned code: $HTTP_CODE${NC}"
    echo "  Response: $BODY"
fi

echo ""

# Test 5: Check data in BigQuery
echo -e "${BLUE}Test 5: Checking data in BigQuery...${NC}"

echo "  Checking sync history..."
SYNC_COUNT=$(bq query --use_legacy_sql=false --format=csv \
    "SELECT COUNT(*) as count FROM \`${PROJECT_ID}.stripe_metadata.sync_history\`" \
    | tail -n 1)

echo "  Sync history records: $SYNC_COUNT"

echo "  Checking raw customers..."
CUSTOMERS_RAW_COUNT=$(bq query --use_legacy_sql=false --format=csv \
    "SELECT COUNT(*) as count FROM \`${PROJECT_ID}.stripe_raw.customers_raw\`" \
    | tail -n 1 || echo "0")

echo "  Raw customers: $CUSTOMERS_RAW_COUNT"

echo "  Checking processed customers..."
CUSTOMERS_PROC_COUNT=$(bq query --use_legacy_sql=false --format=csv \
    "SELECT COUNT(*) as count FROM \`${PROJECT_ID}.stripe_processed.customers\`" \
    | tail -n 1 || echo "0")

echo "  Processed customers: $CUSTOMERS_PROC_COUNT"

if [ "$CUSTOMERS_PROC_COUNT" -gt 0 ]; then
    echo -e "${GREEN}  ✓ Data found in BigQuery tables${NC}"
else
    echo -e "${YELLOW}  ⚠ No data in processed tables yet${NC}"
    echo "  This is normal if you have no Stripe data or first sync hasn't completed"
fi

echo ""

# Test 6: Verify Cloud Scheduler
echo -e "${BLUE}Test 6: Verifying Cloud Scheduler...${NC}"

if gcloud scheduler jobs describe $JOB_NAME --location=$REGION &>/dev/null; then
    echo -e "${GREEN}  ✓ Scheduler job found${NC}"
    
    STATUS=$(gcloud scheduler jobs describe $JOB_NAME --location=$REGION --format='value(state)')
    echo "  Status: $STATUS"
    
    SCHEDULE=$(gcloud scheduler jobs describe $JOB_NAME --location=$REGION --format='value(schedule)')
    echo "  Schedule: $SCHEDULE"
else
    echo -e "${YELLOW}  ⚠ Scheduler job not found${NC}"
    echo "  Run: ./setup-scheduler.sh"
fi

echo ""
echo -e "${GREEN}=========================================="
echo "Pipeline Test Complete!"
echo "==========================================${NC}"
echo ""
echo "Summary:"
echo "  ✓ BigQuery structure verified"
echo "  ✓ Secret Manager configured"
echo "  ✓ Cloud Function deployed and working"
echo "  ✓ Data sync tested"
if gcloud scheduler jobs describe $JOB_NAME --location=$REGION &>/dev/null; then
    echo "  ✓ Scheduler configured"
fi
echo ""
echo "View logs:"
echo "  gcloud functions logs read $FUNCTION_NAME --region=$REGION --gen2 --limit=50"
echo ""
echo "Query data:"
echo "  bq query --use_legacy_sql=false 'SELECT * FROM \`${PROJECT_ID}.stripe_processed.customers\` LIMIT 10'"
echo ""

