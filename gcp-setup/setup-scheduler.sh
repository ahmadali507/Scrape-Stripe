#!/bin/bash
# Set up Cloud Scheduler for the two-component pipeline.
#
# Architecture:
#   Scheduler (4 AM UTC) → AutoCare Cloud Run Job (~1.5h)
#                        → triggers Stripe Cloud Function on completion
#
# This script sets up:
#   1. AutoCare job scheduler (primary)   — triggers autocare-sync-job daily
#   2. Stripe-only scheduler  (optional)  — triggers Stripe function directly
#      for manual re-syncs or testing without running the full AutoCare job

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
CLOUD_RUN_JOB="autocare-sync-job"
SERVICE_ACCOUNT="stripe-sync-sa@${PROJECT_ID}.iam.gserviceaccount.com"

# Scheduler job names
AC_SCHEDULER="autocare-sync-daily"
STRIPE_SCHEDULER="stripe-bigquery-daily-sync"

# Schedules
AC_SCHEDULE="0 4 * * *"      # 4:00 AM UTC  — AutoCare (primary, long-running)
STRIPE_SCHEDULE="0 6 * * *"  # 6:00 AM UTC  — Stripe-only fallback (optional)

# ── 1. AutoCare Cloud Run Job scheduler (primary) ────────────────────────────
echo -e "${YELLOW}Setting up AutoCare Cloud Run Job scheduler...${NC}"

# Verify job exists
if ! gcloud run jobs describe "$CLOUD_RUN_JOB" --region="$REGION" \
         --project="$PROJECT_ID" &>/dev/null; then
    echo -e "${RED}✗ Cloud Run Job '$CLOUD_RUN_JOB' not found.${NC}"
    echo "  Deploy it first: ./deploy-job.sh"
    echo ""
    echo -e "${YELLOW}Skipping AutoCare scheduler setup.${NC}"
else
    # Cloud Run Jobs are triggered via the Run API endpoint
    AC_JOB_URL="https://${REGION}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${PROJECT_ID}/jobs/${CLOUD_RUN_JOB}:run"

    SCHEDULER_ARGS=(
        --location="$REGION"
        --schedule="$AC_SCHEDULE"
        --uri="$AC_JOB_URL"
        --message-body="{}"
        --oauth-service-account-email="$SERVICE_ACCOUNT"
        --time-zone="UTC"
        --attempt-deadline="10800s"
        --description="Daily AutoCare streaming sync (4 AM UTC). Job streams 700k+ records then triggers Stripe function."
    )

    if gcloud scheduler jobs describe "$AC_SCHEDULER" \
           --location="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        echo "  Updating existing scheduler job..."
        gcloud scheduler jobs update http "$AC_SCHEDULER" \
            "${SCHEDULER_ARGS[@]}" --project="$PROJECT_ID"
    else
        echo "  Creating new scheduler job..."
        gcloud scheduler jobs create http "$AC_SCHEDULER" \
            "${SCHEDULER_ARGS[@]}" --project="$PROJECT_ID"
    fi
    echo -e "${GREEN}✓ AutoCare scheduler configured: $AC_SCHEDULE UTC${NC}"
fi
echo ""

# ── 2. Stripe-only scheduler (optional fallback) ─────────────────────────────
echo -e "${YELLOW}Setting up optional Stripe-only scheduler...${NC}"
echo "  This scheduler calls the Stripe function directly with skip_autocare=true."
echo "  Use it for Stripe-only re-syncs, not as the primary daily trigger."
echo ""

# Get Stripe function URL
FUNCTION_URL=$(gcloud functions describe "$FUNCTION_NAME" \
    --region="$REGION" --gen2 --project="$PROJECT_ID" \
    --format='value(serviceConfig.uri)' 2>/dev/null || echo "")

if [ -z "$FUNCTION_URL" ]; then
    echo -e "${YELLOW}⚠ Stripe Cloud Function not deployed — skipping Stripe scheduler.${NC}"
    echo "  Deploy it first: ./deploy-function.sh"
else
    STRIPE_ARGS=(
        --location="$REGION"
        --schedule="$STRIPE_SCHEDULE"
        --uri="$FUNCTION_URL"
        --http-method=POST
        --message-body='{"skip_autocare": true}'
        --headers="Content-Type=application/json"
        --time-zone="UTC"
        --attempt-deadline="540s"
        --max-retry-attempts=3
        --max-backoff=3600s
        --min-backoff=60s
        --description="Stripe-only incremental sync (6 AM UTC). skip_autocare=true — does NOT run AutoCare."
    )

    if gcloud scheduler jobs describe "$STRIPE_SCHEDULER" \
           --location="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        echo "  Updating existing Stripe scheduler job..."
        gcloud scheduler jobs update http "$STRIPE_SCHEDULER" \
            "${STRIPE_ARGS[@]}" --project="$PROJECT_ID"
    else
        echo "  Creating Stripe scheduler job..."
        gcloud scheduler jobs create http "$STRIPE_SCHEDULER" \
            "${STRIPE_ARGS[@]}" --project="$PROJECT_ID"
    fi
    echo -e "${GREEN}✓ Stripe-only scheduler configured: $STRIPE_SCHEDULE UTC${NC}"
fi
echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo -e "${GREEN}=========================================="
echo "Cloud Scheduler Setup Complete!"
echo "==========================================${NC}"
echo ""
echo "  Scheduler jobs:"
echo ""
echo "  ┌─ $AC_SCHEDULER ─────────────────────────────────────────────"
echo "  │  Schedule : $AC_SCHEDULE UTC (4:00 AM daily)"
echo "  │  Triggers : Cloud Run Job ($CLOUD_RUN_JOB)"
echo "  │  Runtime  : ~1.5h — streams all AutoCare records, then calls Stripe function"
echo "  └────────────────────────────────────────────────────────────"
echo ""
echo "  ┌─ $STRIPE_SCHEDULER ──────────────────────────────────────────"
echo "  │  Schedule : $STRIPE_SCHEDULE UTC (6:00 AM daily, optional fallback)"
echo "  │  Triggers : Stripe Cloud Function (skip_autocare=true)"
echo "  │  Runtime  : ~2-5 min — incremental Stripe sync + unified/BI refresh only"
echo "  └────────────────────────────────────────────────────────────"
echo ""
echo "Manual commands:"
echo ""
echo "  Trigger AutoCare job now (full ~1.5h):"
echo "    gcloud run jobs execute $CLOUD_RUN_JOB --region=$REGION --wait"
echo ""
echo "  Trigger Stripe function only (fast):"
echo "    gcloud scheduler jobs run $STRIPE_SCHEDULER --location=$REGION"
echo ""
echo "  Pause AutoCare scheduler:"
echo "    gcloud scheduler jobs pause $AC_SCHEDULER --location=$REGION"
echo ""
echo "  Resume AutoCare scheduler:"
echo "    gcloud scheduler jobs resume $AC_SCHEDULER --location=$REGION"
echo ""
echo "  View all scheduler jobs:"
echo "    gcloud scheduler jobs list --location=$REGION"
echo ""
