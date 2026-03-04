#!/bin/bash
# Test script for the pipeline: one Cloud Function runs AutoCare (stripe-customers)
# + Stripe incremental + unified/BI. One scheduler (stripe-bigquery-daily-sync) triggers it daily.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "Pipeline Test — Stripe + AutoCare"
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
SCHEDULER_JOB="stripe-bigquery-daily-sync"

# ── Helpers ───────────────────────────────────────────────────────────────────
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
    else
        echo -e "  ${RED}✗${NC} $SECRET_NAME = (NOT FOUND or empty)"
    fi
}

bq_count() {
    bq query --use_legacy_sql=false --format=csv \
        "SELECT COUNT(*) as count FROM \`${PROJECT_ID}.$1\`" \
        2>/dev/null | tail -n 1 || echo "0"
}

_show_resource_env() {
    local LABEL="$1"
    local ENV_STRING="$2"
    echo -e "  ${BLUE}$LABEL baked-in env vars:${NC}"
    if [ -n "$ENV_STRING" ]; then
        echo "$ENV_STRING" | tr ',' '\n' | while IFS='=' read -r KEY VAL; do
            case "$KEY" in
                *PASSWORD*|*SECRET*|*KEY*)
                    echo -e "    $KEY = $(_mask "$VAL") (masked)" ;;
                *)
                    echo -e "    $KEY = $VAL" ;;
            esac
        done
    else
        echo "    (none)"
    fi
}

# ── Test 0: Secret Manager credentials ───────────────────────────────────────
echo -e "${BLUE}Test 0: Verifying credentials in Secret Manager...${NC}"
echo ""

echo -e "  ${BLUE}--- AutoCare ---${NC}"
_check_secret "autocare-api-email"    true
_check_secret "autocare-api-password" false

echo -e "  ${BLUE}--- Stripe ---${NC}"
_check_secret "stripe-api-key" false

echo -e "  ${BLUE}--- Replit / GoHighLevel ---${NC}"
_check_secret "replit-webhook-url"    true
_check_secret "replit-webhook-secret" false

echo ""

# Cloud Function env vars
CF_ENV=$(gcloud functions describe "$FUNCTION_NAME" \
    --region="$REGION" --gen2 \
    --format='value(serviceConfig.environmentVariables)' 2>/dev/null || echo "")
_show_resource_env "Cloud Function" "$CF_ENV"

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ── Test 1: BigQuery structure ────────────────────────────────────────────────
echo -e "${BLUE}Test 1: Verifying BigQuery structure...${NC}"

echo "  Checking datasets..."
MISSING=0
for DS in stripe_raw stripe_processed stripe_metadata \
          autocare_raw autocare_processed autocare_metadata \
          unified bi; do
    if bq show --project_id="$PROJECT_ID" "${PROJECT_ID}:${DS}" &>/dev/null; then
        echo -e "    ${GREEN}✓${NC} $DS"
    else
        echo -e "    ${RED}✗${NC} $DS — not found"
        MISSING=1
    fi
done
[ "$MISSING" -ne 0 ] && echo -e "${RED}  ✗ Missing datasets. Run: ./create-tables.sh${NC}" && exit 1
echo -e "${GREEN}  ✓ All datasets found${NC}"
echo ""

echo "  Checking Stripe tables..."
for TBL in customers_raw subscriptions_raw; do
    bq show --project_id="$PROJECT_ID" "stripe_raw.${TBL}" &>/dev/null \
        && echo -e "    ${GREEN}✓${NC} stripe_raw.$TBL" \
        || { echo -e "    ${RED}✗${NC} stripe_raw.$TBL — missing"; MISSING=1; }
done
[ "$MISSING" -ne 0 ] && echo -e "${RED}  ✗ Run: ./create-tables.sh${NC}" && exit 1
echo ""

echo "  Checking AutoCare processed tables..."
for TBL in tiers marketing_customers marketing_subscriptions \
           marketing_sessions marketing_cars; do
    bq show --project_id="$PROJECT_ID" "autocare_processed.${TBL}" &>/dev/null \
        && echo -e "    ${GREEN}✓${NC} autocare_processed.$TBL" \
        || echo -e "    ${RED}✗${NC} autocare_processed.$TBL — missing (run ./create-tables.sh)"
done

echo ""
echo "  Checking AutoCare raw (stripe_customers_raw)..."
bq show --project_id="$PROJECT_ID" "autocare_raw.stripe_customers_raw" &>/dev/null \
    && echo -e "    ${GREEN}✓${NC} autocare_raw.stripe_customers_raw" \
    || echo -e "    ${YELLOW}⚠${NC} autocare_raw.stripe_customers_raw — run ./create-tables.sh"
echo ""

echo "  Checking unified / BI tables..."
for TBL_SPEC in "unified.customers" "bi.unified_customer_360_snapshot"; do
    if bq show --project_id="$PROJECT_ID" "${TBL_SPEC}" &>/dev/null; then
        echo -e "    ${GREEN}✓${NC} ${TBL_SPEC}"
    else
        echo -e "    ${YELLOW}⚠${NC} ${TBL_SPEC} — not yet populated (normal before first sync)"
    fi
done
echo ""

# ── Test 2: Secret Manager ────────────────────────────────────────────────────
echo -e "${BLUE}Test 2: Verifying Secret Manager secrets...${NC}"
SM_OK=1
for SECRET in stripe-api-key autocare-api-email autocare-api-password; do
    if gcloud secrets describe "$SECRET" --project="$PROJECT_ID" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $SECRET exists"
    else
        echo -e "  ${RED}✗${NC} $SECRET NOT FOUND — run ./setup-secrets.sh"
        SM_OK=0
    fi
done
[ "$SM_OK" -eq 0 ] && exit 1
echo ""

# ── Test 3: Cloud Function ───────────────────────────────────────────────────
echo -e "${BLUE}Test 3: Verifying Cloud Function...${NC}"

if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" --gen2 \
       --project="$PROJECT_ID" &>/dev/null; then
    FUNCTION_URL=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" --gen2 \
        --format='value(serviceConfig.uri)')
    echo -e "  ${GREEN}✓${NC} Cloud Function deployed"
    echo "    URL: $FUNCTION_URL"
else
    echo -e "  ${RED}✗${NC} Cloud Function NOT deployed — run: ./deploy-function.sh"
    FUNCTION_URL=""
fi
echo ""

# ── Test 4: Full sync smoke-test (AutoCare + Stripe + unified/BI, ~1-3 min) ───
echo -e "${BLUE}Test 4: Full sync (AutoCare stripe-customers + Stripe + unified/BI)...${NC}"
echo ""

if [ -z "$FUNCTION_URL" ]; then
    echo -e "  ${RED}✗ Skipping — Cloud Function not deployed${NC}"
else
    echo "  Invoking Cloud Function (no body = full sync)..."
    RESPONSE=$(curl -s -X POST "$FUNCTION_URL" \
        -H "Content-Type: application/json" \
        -w "\n%{http_code}" \
        --max-time 600)

    HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
    BODY=$(echo "$RESPONSE" | head -n -1)

    if [ "$HTTP_CODE" = "200" ]; then
        echo -e "  ${GREEN}✓ Function executed successfully (HTTP 200)${NC}"
    else
        echo -e "  ${YELLOW}⚠ Function returned HTTP $HTTP_CODE${NC}"
    fi
    echo "  Response: $BODY"
fi
echo ""

# ── Test 5: BigQuery row counts ───────────────────────────────────────────────
echo -e "${BLUE}Test 5: BigQuery row counts...${NC}"

echo "  --- Stripe ---"
echo "  stripe_metadata.sync_history        : $(bq_count "stripe_metadata.sync_history") rows"
echo "  stripe_raw.customers_raw            : $(bq_count "stripe_raw.customers_raw") rows"
echo "  stripe_processed.customers          : $(bq_count "stripe_processed.customers") rows"
echo "  stripe_processed.subscriptions      : $(bq_count "stripe_processed.subscriptions") rows"

echo ""
echo "  --- AutoCare raw ---"
echo "  autocare_raw.tiers_raw              : $(bq_count "autocare_raw.tiers_raw") rows"
echo "  autocare_raw.stripe_customers_raw   : $(bq_count "autocare_raw.stripe_customers_raw") rows"

echo ""
echo "  --- AutoCare processed ---"
echo "  autocare_processed.tiers            : $(bq_count "autocare_processed.tiers") rows"
AC_CUST=$(bq_count "autocare_processed.marketing_customers")
echo "  autocare_processed.marketing_customers     : $AC_CUST rows"
echo "  autocare_processed.marketing_subscriptions : $(bq_count "autocare_processed.marketing_subscriptions") rows"
echo "  autocare_processed.marketing_sessions      : $(bq_count "autocare_processed.marketing_sessions") rows"
echo "  autocare_processed.marketing_cars          : $(bq_count "autocare_processed.marketing_cars") rows"

echo ""
echo "  --- Unified / BI ---"
UNIFIED_COUNT=$(bq_count "unified.customers")
BI_COUNT=$(bq_count "bi.unified_customer_360_snapshot")
echo "  unified.customers                          : $UNIFIED_COUNT rows"
echo "  bi.unified_customer_360_snapshot           : $BI_COUNT rows"

echo ""
[ "$UNIFIED_COUNT" -gt 0 ] \
    && echo -e "  ${GREEN}✓ unified.customers populated${NC}" \
    || echo -e "  ${YELLOW}⚠ unified.customers empty — populated after first successful sync${NC}"
[ "$BI_COUNT" -gt 0 ] \
    && echo -e "  ${GREEN}✓ bi.unified_customer_360_snapshot populated${NC}" \
    || echo -e "  ${YELLOW}⚠ bi.unified_customer_360_snapshot empty${NC}"
echo ""

# ── Test 6: Cloud Scheduler ───────────────────────────────────────────────────
echo -e "${BLUE}Test 6: Verifying Cloud Scheduler...${NC}"
if gcloud scheduler jobs describe "$SCHEDULER_JOB" \
       --location="$REGION" --project="$PROJECT_ID" &>/dev/null; then
    S_STATUS=$(gcloud scheduler jobs describe "$SCHEDULER_JOB" \
        --location="$REGION" --format='value(state)' 2>/dev/null)
    S_SCHEDULE=$(gcloud scheduler jobs describe "$SCHEDULER_JOB" \
        --location="$REGION" --format='value(schedule)' 2>/dev/null)
    echo -e "  ${GREEN}✓${NC} $SCHEDULER_JOB"
    echo "    Schedule : $S_SCHEDULE UTC"
    echo "    State    : $S_STATUS"
else
    echo -e "  ${YELLOW}⚠${NC} $SCHEDULER_JOB not found — run: ./setup-scheduler.sh"
fi
echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo -e "${GREEN}=========================================="
echo "Pipeline Test Complete!"
echo "==========================================${NC}"
echo ""
echo "Architecture:"
echo "  Cloud Scheduler ($SCHEDULER_JOB at 4 AM UTC)"
echo "    └─▶ Cloud Function ($FUNCTION_NAME): AutoCare (stripe-customers) + Stripe + unified/BI"
echo ""
echo "Manual commands:"
echo "  Trigger full sync:  gcloud scheduler jobs run $SCHEDULER_JOB --location=$REGION"
echo "  Or:  curl -X POST \$FUNCTION_URL -H 'Content-Type: application/json'"
echo ""
echo "  View function logs:"
echo "    gcloud functions logs read $FUNCTION_NAME --region=$REGION --gen2 --limit=50"
echo ""
echo "  Check AutoCare sync metadata:"
echo "    bq query --use_legacy_sql=false 'SELECT * FROM \`${PROJECT_ID}.autocare_metadata.sync_history\` ORDER BY sync_completed_at DESC LIMIT 5'"
echo ""
echo "  Check Stripe sync metadata:"
echo "    bq query --use_legacy_sql=false 'SELECT * FROM \`${PROJECT_ID}.stripe_metadata.sync_history\` ORDER BY sync_completed_at DESC LIMIT 5'"
echo ""
