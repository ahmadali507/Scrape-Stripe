#!/bin/bash
# Test script for the two-component pipeline:
#
#   Component 1 — AutoCare Cloud Run Job  (autocare-sync-job)
#     Streams 700k+ records, ~1.5h, triggers Component 2 on completion
#
#   Component 2 — Stripe Cloud Function   (stripe-bigquery-sync)
#     Incremental Stripe sync + unified/BI refresh, ~2-5 min
#     Scheduled independently; also called by the Cloud Run Job
#
# Test 4 triggers ONLY the Stripe function (skip_autocare=true) for a
# fast smoke-test. The full AutoCare job takes ~1.5h and must be triggered
# manually via:  gcloud run jobs execute autocare-sync-job --region=us-central1

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
CLOUD_RUN_JOB="autocare-sync-job"
REGION="us-central1"
AC_SCHEDULER="autocare-sync-daily"
STRIPE_SCHEDULER="stripe-bigquery-daily-sync"

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
_show_resource_env "Stripe Cloud Function" "$CF_ENV"

echo ""

# Cloud Run Job env vars
JOB_ENV=$(gcloud run jobs describe "$CLOUD_RUN_JOB" \
    --region="$REGION" \
    --format='value(spec.template.spec.template.spec.containers[0].env)' \
    2>/dev/null || echo "")
# Alternative format if above fails
if [ -z "$JOB_ENV" ]; then
    JOB_ENV=$(gcloud run jobs describe "$CLOUD_RUN_JOB" \
        --region="$REGION" \
        --format='json' 2>/dev/null \
        | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    envs = d['spec']['template']['spec']['template']['spec']['containers'][0].get('env', [])
    print(','.join(f\"{e['name']}={e.get('value','')}\" for e in envs))
except: pass" 2>/dev/null || echo "")
fi
_show_resource_env "AutoCare Cloud Run Job" "$JOB_ENV"

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
echo "  Checking AutoCare staging tables (required by Cloud Run Job)..."
STAGING_OK=1
for TBL in staging_customers staging_subscriptions staging_sessions staging_cars; do
    if bq show --project_id="$PROJECT_ID" "autocare_processed.${TBL}" &>/dev/null; then
        echo -e "    ${GREEN}✓${NC} autocare_processed.$TBL"
    else
        echo -e "    ${RED}✗${NC} autocare_processed.$TBL — missing (run ./create-tables.sh)"
        STAGING_OK=0
    fi
done
[ "$STAGING_OK" -eq 0 ] && echo -e "  ${RED}✗ Staging tables missing — Cloud Run Job will fail${NC}"
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

# ── Test 3: Verify both compute resources ─────────────────────────────────────
echo -e "${BLUE}Test 3: Verifying compute resources...${NC}"

# 3a — Stripe Cloud Function
if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" --gen2 \
       --project="$PROJECT_ID" &>/dev/null; then
    FUNCTION_URL=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" --gen2 \
        --format='value(serviceConfig.uri)')
    echo -e "  ${GREEN}✓${NC} Stripe Cloud Function deployed"
    echo "    URL: $FUNCTION_URL"
else
    echo -e "  ${RED}✗${NC} Stripe Cloud Function NOT deployed — run: ./deploy-function.sh"
    FUNCTION_URL=""
fi

echo ""

# 3b — AutoCare Cloud Run Job
if gcloud run jobs describe "$CLOUD_RUN_JOB" --region="$REGION" \
       --project="$PROJECT_ID" &>/dev/null; then
    JOB_CREATED=$(gcloud run jobs describe "$CLOUD_RUN_JOB" \
        --region="$REGION" --format='value(metadata.creationTimestamp)' 2>/dev/null || echo "unknown")
    JOB_IMAGE=$(gcloud run jobs describe "$CLOUD_RUN_JOB" \
        --region="$REGION" \
        --format='value(spec.template.spec.template.spec.containers[0].image)' 2>/dev/null || echo "unknown")
    echo -e "  ${GREEN}✓${NC} AutoCare Cloud Run Job deployed"
    echo "    Image  : $JOB_IMAGE"
    echo "    Created: $JOB_CREATED"
else
    echo -e "  ${YELLOW}⚠${NC} AutoCare Cloud Run Job NOT deployed — run: ./deploy-job.sh"
fi
echo ""

# ── Test 4: Stripe smoke-test (skip_autocare=true, fast ~2-5 min) ─────────────
echo -e "${BLUE}Test 4: Stripe smoke-test (skip_autocare=true, ~2-5 min)...${NC}"
echo ""
echo -e "  ${YELLOW}Note: This tests ONLY the Stripe sync + unified/BI refresh.${NC}"
echo -e "  ${YELLOW}To test the full AutoCare job (~1.5h) run manually:${NC}"
echo -e "  ${YELLOW}  gcloud run jobs execute $CLOUD_RUN_JOB --region=$REGION${NC}"
echo ""

if [ -z "$FUNCTION_URL" ]; then
    echo -e "  ${RED}✗ Skipping — Stripe Cloud Function not deployed${NC}"
else
    echo "  Invoking Stripe Cloud Function with skip_autocare=true ..."
    RESPONSE=$(curl -s -X POST "$FUNCTION_URL" \
        -H "Content-Type: application/json" \
        -d '{"skip_autocare": true}' \
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
echo "  autocare_raw.marketing_data_raw     : $(bq_count "autocare_raw.marketing_data_raw") rows"

echo ""
echo "  --- AutoCare processed ---"
echo "  autocare_processed.tiers            : $(bq_count "autocare_processed.tiers") rows"
AC_CUST=$(bq_count "autocare_processed.marketing_customers")
echo "  autocare_processed.marketing_customers     : $AC_CUST rows"
echo "  autocare_processed.marketing_subscriptions : $(bq_count "autocare_processed.marketing_subscriptions") rows"
echo "  autocare_processed.marketing_sessions      : $(bq_count "autocare_processed.marketing_sessions") rows"
echo "  autocare_processed.marketing_cars          : $(bq_count "autocare_processed.marketing_cars") rows"

echo ""
echo "  --- AutoCare staging (should be 0 when no job is running) ---"
echo "  autocare_processed.staging_customers       : $(bq_count "autocare_processed.staging_customers") rows"
echo "  autocare_processed.staging_subscriptions   : $(bq_count "autocare_processed.staging_subscriptions") rows"
echo "  autocare_processed.staging_sessions        : $(bq_count "autocare_processed.staging_sessions") rows"
echo "  autocare_processed.staging_cars            : $(bq_count "autocare_processed.staging_cars") rows"

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

# ── Test 6: Cloud Scheduler jobs ─────────────────────────────────────────────
echo -e "${BLUE}Test 6: Verifying Cloud Scheduler jobs...${NC}"
echo ""

# 6a — AutoCare Cloud Run Job scheduler (primary)
echo -e "  ${BLUE}--- AutoCare job scheduler (primary) ---${NC}"
if gcloud scheduler jobs describe "$AC_SCHEDULER" \
       --location="$REGION" --project="$PROJECT_ID" &>/dev/null; then
    AC_STATUS=$(gcloud scheduler jobs describe "$AC_SCHEDULER" \
        --location="$REGION" --format='value(state)' 2>/dev/null)
    AC_SCHEDULE=$(gcloud scheduler jobs describe "$AC_SCHEDULER" \
        --location="$REGION" --format='value(schedule)' 2>/dev/null)
    AC_LAST=$(gcloud scheduler jobs describe "$AC_SCHEDULER" \
        --location="$REGION" --format='value(lastAttemptTime)' 2>/dev/null || echo "never")
    echo -e "  ${GREEN}✓${NC} $AC_SCHEDULER"
    echo "    Schedule    : $AC_SCHEDULE UTC"
    echo "    State       : $AC_STATUS"
    echo "    Last attempt: $AC_LAST"
else
    echo -e "  ${YELLOW}⚠${NC} $AC_SCHEDULER not found — run: ./deploy-job.sh"
fi
echo ""

# 6b — Direct Stripe-only scheduler (optional fallback)
echo -e "  ${BLUE}--- Stripe-only scheduler (optional fallback) ---${NC}"
if gcloud scheduler jobs describe "$STRIPE_SCHEDULER" \
       --location="$REGION" --project="$PROJECT_ID" &>/dev/null; then
    S_STATUS=$(gcloud scheduler jobs describe "$STRIPE_SCHEDULER" \
        --location="$REGION" --format='value(state)' 2>/dev/null)
    S_SCHEDULE=$(gcloud scheduler jobs describe "$STRIPE_SCHEDULER" \
        --location="$REGION" --format='value(schedule)' 2>/dev/null)
    echo -e "  ${GREEN}✓${NC} $STRIPE_SCHEDULER"
    echo "    Schedule : $S_SCHEDULE UTC"
    echo "    State    : $S_STATUS"
    echo -e "    ${YELLOW}Note: Only use this for Stripe-only re-syncs; AutoCare job triggers Stripe automatically${NC}"
else
    echo -e "  ${YELLOW}ℹ${NC} $STRIPE_SCHEDULER not configured (optional — run ./setup-scheduler.sh to add)"
fi
echo ""

# ── Test 7: Recent Cloud Run Job executions ───────────────────────────────────
echo -e "${BLUE}Test 7: Recent AutoCare job executions...${NC}"
if gcloud run jobs describe "$CLOUD_RUN_JOB" --region="$REGION" \
       --project="$PROJECT_ID" &>/dev/null; then
    EXECS=$(gcloud run jobs executions list \
        --job="$CLOUD_RUN_JOB" \
        --region="$REGION" \
        --limit=5 \
        --format='table(name.basename(),completionTime,status.conditions[0].type)' \
        2>/dev/null || echo "  (no executions yet)")
    echo "$EXECS"
else
    echo -e "  ${YELLOW}⚠${NC} Cloud Run Job not deployed — no executions to show"
fi
echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo -e "${GREEN}=========================================="
echo "Pipeline Test Complete!"
echo "==========================================${NC}"
echo ""
echo "Architecture:"
echo "  Cloud Scheduler ($AC_SCHEDULER at 4 AM UTC)"
echo "    └─▶ AutoCare Cloud Run Job ($CLOUD_RUN_JOB, ~1.5h)"
echo "          └─▶ Stripe Cloud Function ($FUNCTION_NAME, ~2-5 min)"
echo "                └─▶ unified.customers + bi.unified_customer_360_snapshot"
echo ""
echo "Manual commands:"
echo ""
echo "  Run AutoCare job (full ~1.5h sync + triggers Stripe):"
echo "    gcloud run jobs execute $CLOUD_RUN_JOB --region=$REGION --wait"
echo ""
echo "  Run Stripe-only (fast, incremental):"
echo "    curl -X POST \$FUNCTION_URL -H 'Content-Type: application/json' -d '{\"skip_autocare\": true}'"
echo ""
echo "  View AutoCare job logs:"
echo "    gcloud run jobs executions list --job=$CLOUD_RUN_JOB --region=$REGION"
echo "    gcloud logging read 'resource.type=cloud_run_job' --limit=100 --project=$PROJECT_ID"
echo ""
echo "  View Stripe function logs:"
echo "    gcloud functions logs read $FUNCTION_NAME --region=$REGION --gen2 --limit=50"
echo ""
echo "  Check AutoCare sync metadata:"
echo "    bq query --use_legacy_sql=false 'SELECT * FROM \`${PROJECT_ID}.autocare_metadata.sync_history\` ORDER BY sync_completed_at DESC LIMIT 5'"
echo ""
echo "  Check Stripe sync metadata:"
echo "    bq query --use_legacy_sql=false 'SELECT * FROM \`${PROJECT_ID}.stripe_metadata.sync_history\` ORDER BY sync_completed_at DESC LIMIT 5'"
echo ""
