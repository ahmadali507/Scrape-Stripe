#!/bin/bash
# Remove the redundant AutoCare Cloud Run Job and its scheduler.
# After switching to stripe-customers, the Cloud Function runs AutoCare + Stripe in one flow;
# the job and autocare-sync-daily scheduler are no longer used.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "Cleanup: Remove redundant Job and Scheduler"
echo "=========================================="
echo ""

PROJECT_ID=$(gcloud config get-value project)
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}Error: No GCP project selected${NC}"
    exit 1
fi

REGION="us-central1"
CLOUD_RUN_JOB="autocare-sync-job"
AC_SCHEDULER="autocare-sync-daily"

# ── 1. Delete the AutoCare Cloud Run Job ─────────────────────────────
echo -e "${YELLOW}1. Deleting Cloud Run Job: $CLOUD_RUN_JOB${NC}"
if gcloud run jobs describe "$CLOUD_RUN_JOB" --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
    gcloud run jobs delete "$CLOUD_RUN_JOB" --region="$REGION" --project="$PROJECT_ID" --quiet
    echo -e "${GREEN}   ✓ Deleted $CLOUD_RUN_JOB${NC}"
else
    echo "   (Job not found — already deleted or never created)"
fi
echo ""

# ── 2. Delete the scheduler that triggered the job ───────────────────
echo -e "${YELLOW}2. Deleting Scheduler: $AC_SCHEDULER${NC}"
if gcloud scheduler jobs describe "$AC_SCHEDULER" --location="$REGION" --project="$PROJECT_ID" &>/dev/null; then
    gcloud scheduler jobs delete "$AC_SCHEDULER" --location="$REGION" --project="$PROJECT_ID" --quiet
    echo -e "${GREEN}   ✓ Deleted $AC_SCHEDULER${NC}"
else
    echo "   (Scheduler not found — already deleted or never created)"
fi
echo ""

echo -e "${GREEN}=========================================="
echo "Cleanup complete"
echo "==========================================${NC}"
echo ""
echo "Remaining: One scheduler (stripe-bigquery-daily-sync) triggers the Cloud Function"
echo "which now runs AutoCare (stripe-customers) + Stripe + unified/BI in one go."
echo ""
echo "To ensure the single scheduler is configured: ./setup-scheduler.sh"
echo ""
