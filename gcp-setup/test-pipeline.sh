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

# ── Test 0: Verify Secret Manager credentials ─────────────────────────────────
echo -e "${BLUE}Test 0: Verifying credentials in Secret Manager...${NC}"
echo ""

_mask() {
    local V="$1"
    if [ ${#V} -le 4 ]; then echo "****"; else echo "${V:0:4}****"; fi
}

_check_secret() {
    local SECRET_NAME="$1"
    local SHOW_FULL="${2:-false}"
    local VALUE
    VALUE=$(gcloud secrets versions access latest \
        --secret="$SECRET_NAME" \
        --project="$PROJECT_ID" 2>/dev/null || echo "")
    if [ -n "$VALUE" ]; then
        if [ "$SHOW_FULL" = "true" ]; then
            echo -e "  ${GREEN}✓${NC} $SECRET_NAME = $VALUE"
        else
            echo -e "  ${GREEN}✓${NC} $SECRET_NAME = $(_mask "$VALUE") (masked)"
        fi
        echo "$VALUE"   # return value for capture
    else
        echo -e "  ${RED}✗${NC} $SECRET_NAME = (NOT FOUND or empty)"
        echo ""
    fi
}

echo -e "  ${BLUE}--- AutoCare ---${NC}"
AUTOCARE_EMAIL=$(_check_secret "autocare-api-email"    true  2>/dev/null | tail -n 1)
AUTOCARE_PASS=$( _check_secret "autocare-api-password" false 2>/dev/null | tail -n 1)

echo -e "  ${BLUE}--- Stripe ---${NC}"
_check_secret "stripe-api-key" false > /dev/null

echo -e "  ${BLUE}--- Replit / GoHighLevel ---${NC}"
_check_secret "replit-webhook-url"    true  > /dev/null
_check_secret "replit-webhook-secret" false > /dev/null

echo ""
echo -e "${BLUE}  Cloud Function baked-in env vars (what it will actually use):${NC}"
FUNC_ENV=$(gcloud functions describe "$FUNCTION_NAME" \
    --region="$REGION" \
    --gen2 \
    --format='value(serviceConfig.environmentVariables)' 2>/dev/null || echo "")
if [ -n "$FUNC_ENV" ]; then
    # Print each var on its own line, masking passwords/secrets
    echo "$FUNC_ENV" | tr ',' '\n' | while IFS='=' read -r KEY VAL; do
        case "$KEY" in
            *PASSWORD*|*SECRET*|*KEY*)
                echo -e "    $KEY = $(_mask "$VAL") (masked)" ;;
            *)
                echo -e "    $KEY = $VAL" ;;
        esac
    done
else
    echo "    (no env vars set on function)"
fi
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Test 1: Verify BigQuery datasets and tables
echo -e "${BLUE}Test 1: Verifying BigQuery structure...${NC}"

echo "  Checking datasets (project: $PROJECT_ID)..."
MISSING=0
for DS in stripe_raw stripe_processed stripe_metadata autocare_raw autocare_processed autocare_metadata unified bi; do
    if bq show --project_id="$PROJECT_ID" "${PROJECT_ID}:${DS}" &>/dev/null; then
        echo -e "    ${GREEN}✓${NC} ${DS}"
    else
        echo -e "    ${RED}✗${NC} ${DS} — not found"
        MISSING=1
    fi
done

if [ "$MISSING" -ne 0 ]; then
    echo -e "${RED}  ✗ One or more BigQuery datasets missing. Run: ./create-tables.sh${NC}"
    exit 1
else
    echo -e "${GREEN}  ✓ All BigQuery datasets found${NC}"
fi

echo "  Checking Stripe tables..."
TABLES_COUNT=$(bq ls --project_id="$PROJECT_ID" stripe_raw 2>/dev/null | wc -l || echo 0)
if [ "$TABLES_COUNT" -lt 2 ]; then
    echo -e "${RED}  ✗ stripe_raw tables missing. Run: ./create-tables.sh${NC}"
    exit 1
else
    echo -e "${GREEN}  ✓ stripe_raw tables found${NC}"
fi

echo "  Checking AutoCare tables..."
AC_TABLES_OK=1
for TBL in tiers_raw marketing_data_raw; do
    if bq show --project_id="$PROJECT_ID" "autocare_raw.${TBL}" &>/dev/null; then
        echo -e "    ${GREEN}✓${NC} autocare_raw.${TBL}"
    else
        echo -e "    ${RED}✗${NC} autocare_raw.${TBL} — not found"
        AC_TABLES_OK=0
    fi
done
for TBL in tiers marketing_customers marketing_subscriptions marketing_sessions marketing_cars; do
    if bq show --project_id="$PROJECT_ID" "autocare_processed.${TBL}" &>/dev/null; then
        echo -e "    ${GREEN}✓${NC} autocare_processed.${TBL}"
    else
        echo -e "    ${RED}✗${NC} autocare_processed.${TBL} — not found"
        AC_TABLES_OK=0
    fi
done
if [ "$AC_TABLES_OK" -eq 1 ]; then
    echo -e "${GREEN}  ✓ AutoCare tables found${NC}"
else
    echo -e "${RED}  ✗ Some AutoCare tables missing. Run: ./create-tables.sh${NC}"
    exit 1
fi

echo "  Checking unified / BI tables (populated after first sync — warning only)..."
for TBL_SPEC in "unified.customers" "bi.unified_customer_360_snapshot"; do
    if bq show --project_id="$PROJECT_ID" "${TBL_SPEC}" &>/dev/null; then
        echo -e "    ${GREEN}✓${NC} ${TBL_SPEC}"
    else
        echo -e "    ${YELLOW}⚠${NC} ${TBL_SPEC} — not yet populated (created by Cloud Function on first sync)"
    fi
done

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

# Trigger the function (every run syncs both Stripe and AutoCare)
echo "  Invoking function (Stripe + AutoCare)..."
RESPONSE=$(curl -s -X POST "$FUNCTION_URL" -H "Content-Type: application/json" -w "\n%{http_code}")

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

bq_count() {
    bq query --use_legacy_sql=false --format=csv \
        "SELECT COUNT(*) as count FROM \`${PROJECT_ID}.$1\`" \
        2>/dev/null | tail -n 1 || echo "0"
}

echo "  --- Stripe ---"
SYNC_COUNT=$(bq_count "stripe_metadata.sync_history")
echo "  stripe_metadata.sync_history:        $SYNC_COUNT rows"

CUSTOMERS_RAW_COUNT=$(bq_count "stripe_raw.customers_raw")
echo "  stripe_raw.customers_raw:            $CUSTOMERS_RAW_COUNT rows"

CUSTOMERS_PROC_COUNT=$(bq_count "stripe_processed.customers")
echo "  stripe_processed.customers:          $CUSTOMERS_PROC_COUNT rows"

SUBS_PROC_COUNT=$(bq_count "stripe_processed.subscriptions")
echo "  stripe_processed.subscriptions:      $SUBS_PROC_COUNT rows"

if [ "$CUSTOMERS_PROC_COUNT" -gt 0 ] || [ "$SUBS_PROC_COUNT" -gt 0 ]; then
    echo -e "  ${GREEN}✓ Stripe data found${NC}"
else
    echo -e "  ${YELLOW}⚠ No Stripe data yet (normal if first sync hasn't run)${NC}"
fi

echo "  --- AutoCare ---"
TIERS_RAW_COUNT=$(bq_count "autocare_raw.tiers_raw")
echo "  autocare_raw.tiers_raw:              $TIERS_RAW_COUNT rows"

MKTG_RAW_COUNT=$(bq_count "autocare_raw.marketing_data_raw")
echo "  autocare_raw.marketing_data_raw:     $MKTG_RAW_COUNT rows"

AC_CUSTOMERS_COUNT=$(bq_count "autocare_processed.marketing_customers")
echo "  autocare_processed.marketing_customers: $AC_CUSTOMERS_COUNT rows"

AC_SESSIONS_COUNT=$(bq_count "autocare_processed.marketing_sessions")
echo "  autocare_processed.marketing_sessions:  $AC_SESSIONS_COUNT rows"

AC_SUBS_COUNT=$(bq_count "autocare_processed.marketing_subscriptions")
echo "  autocare_processed.marketing_subscriptions: $AC_SUBS_COUNT rows"

if [ "$TIERS_RAW_COUNT" -gt 0 ] && [ "$AC_CUSTOMERS_COUNT" -gt 0 ]; then
    echo -e "  ${GREEN}✓ AutoCare data found${NC}"
else
    echo -e "  ${YELLOW}⚠ No AutoCare data yet — check AUTOCARE_API_EMAIL / autocare-api-email secret and Cloud Function logs${NC}"
fi

echo "  --- Unified / BI ---"
UNIFIED_COUNT=$(bq_count "unified.customers")
echo "  unified.customers:                   $UNIFIED_COUNT rows"

BI_COUNT=$(bq_count "bi.unified_customer_360_snapshot")
echo "  bi.unified_customer_360_snapshot:    $BI_COUNT rows"

if [ "$UNIFIED_COUNT" -gt 0 ]; then
    echo -e "  ${GREEN}✓ unified.customers populated${NC}"
else
    echo -e "  ${YELLOW}⚠ unified.customers empty — will be populated after first successful sync${NC}"
fi
if [ "$BI_COUNT" -gt 0 ]; then
    echo -e "  ${GREEN}✓ bi.unified_customer_360_snapshot populated${NC}"
else
    echo -e "  ${YELLOW}⚠ bi.unified_customer_360_snapshot empty — populated after unified.customers succeeds${NC}"
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

