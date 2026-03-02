#!/bin/bash
# Deploy AutoCare sync as a Cloud Run Job.
#
# Architecture:
#   Cloud Scheduler → Cloud Run Job (AutoCare streaming, ~1.5h)
#                   → triggers Stripe Cloud Function on completion
#
# The job streams 700k+ AutoCare records page-by-page to BigQuery,
# then calls the Stripe Cloud Function with skip_autocare=true so
# Stripe incremental sync + unified/BI refresh runs after.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "Deploy AutoCare Cloud Run Job"
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
JOB_NAME="autocare-sync-job"
REPO_NAME="autocare-sync"
IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$JOB_NAME:latest"
SERVICE_ACCOUNT="stripe-sync-sa@${PROJECT_ID}.iam.gserviceaccount.com"
MEMORY="1Gi"
CPU="1"
TIMEOUT="10800s"   # 3 hours (2× safety margin over observed 1.5h runtime)
MAX_RETRIES="1"
SCHEDULER_JOB="autocare-sync-daily"
SCHEDULER_SCHEDULE="0 4 * * *"   # 4:00 AM UTC daily

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SOURCE_DIR="$SCRIPT_DIR/../cloud-function"
SQL_DIR="$SCRIPT_DIR/../sql"

# ── Load latest credentials from Secret Manager ──────────────────────────────
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
        echo -e "${GREEN}  ✓ $SECRET_NAME loaded${NC}"
    else
        echo -e "${YELLOW}  ⚠ $SECRET_NAME not found — $ENV_VAR will not be set${NC}"
    fi
}

_mask() {
    local V="$1"
    if [ ${#V} -le 4 ]; then echo "****"; else echo "${V:0:4}****"; fi
}

_load_secret "autocare-api-email"    AUTOCARE_API_EMAIL
_load_secret "autocare-api-password" AUTOCARE_API_PASSWORD
_load_secret "replit-webhook-url"    REPLIT_WEBHOOK_URL
_load_secret "replit-webhook-secret" REPLIT_WEBHOOK_SECRET

echo ""
echo -e "${BLUE}━━━━ Credentials resolved ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  AUTOCARE_API_EMAIL    = ${AUTOCARE_API_EMAIL:-(NOT SET — job will fail)}"
[ -n "$AUTOCARE_API_PASSWORD" ] \
    && echo -e "  AUTOCARE_API_PASSWORD = $(_mask "$AUTOCARE_API_PASSWORD") (masked)" \
    || echo -e "  AUTOCARE_API_PASSWORD = (NOT SET — job will fail)"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ── Copy BI snapshot SQL into cloud-function/sql/ for the Docker build ────────
mkdir -p "$SOURCE_DIR/sql"
if [ -f "$SQL_DIR/create_bi_customer_360_snapshot.sql" ]; then
    cp "$SQL_DIR/create_bi_customer_360_snapshot.sql" "$SOURCE_DIR/sql/"
    echo -e "${GREEN}✓ BI snapshot SQL copied to cloud-function/sql/${NC}"
fi

# ── Enable required APIs ──────────────────────────────────────────────────────
echo -e "${YELLOW}Enabling required GCP APIs...${NC}"
gcloud services enable \
    artifactregistry.googleapis.com \
    run.googleapis.com \
    cloudbuild.googleapis.com \
    cloudscheduler.googleapis.com \
    --project="$PROJECT_ID" --quiet
echo -e "${GREEN}✓ APIs enabled${NC}"
echo ""

# ── Grant service account Cloud Run Job invoker role (needed by Scheduler) ───
echo -e "${YELLOW}Granting run.invoker role to service account...${NC}"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SERVICE_ACCOUNT" \
    --role="roles/run.invoker" \
    --quiet 2>/dev/null || true
echo -e "${GREEN}✓ IAM role granted${NC}"
echo ""

# ── Create Artifact Registry repository (idempotent) ─────────────────────────
echo -e "${YELLOW}Creating Artifact Registry repository ($REPO_NAME)...${NC}"
gcloud artifacts repositories create "$REPO_NAME" \
    --repository-format=docker \
    --location="$REGION" \
    --description="AutoCare Cloud Run Job Docker images" \
    --project="$PROJECT_ID" \
    2>/dev/null || echo -e "${GREEN}  (already exists)${NC}"
echo -e "${GREEN}✓ Artifact Registry repository ready${NC}"
echo ""

# ── Build and push Docker image via Cloud Build ───────────────────────────────
echo -e "${YELLOW}Building Docker image with Cloud Build...${NC}"
echo "  Image: $IMAGE"
echo ""
gcloud builds submit "$SOURCE_DIR" \
    --tag="$IMAGE" \
    --project="$PROJECT_ID"
echo ""
echo -e "${GREEN}✓ Docker image built and pushed${NC}"
echo ""

# ── Get Stripe Cloud Function URL ─────────────────────────────────────────────
STRIPE_FUNCTION_URL=$(gcloud functions describe stripe-bigquery-sync \
    --region="$REGION" \
    --gen2 \
    --project="$PROJECT_ID" \
    --format='value(serviceConfig.uri)' 2>/dev/null || echo "")

if [ -z "$STRIPE_FUNCTION_URL" ]; then
    echo -e "${YELLOW}⚠ Stripe Cloud Function not found. Deploy it first with ./deploy-function.sh${NC}"
    echo "  STRIPE_FUNCTION_URL will be empty; Stripe sync will not auto-trigger after AutoCare job."
else
    echo -e "${GREEN}✓ Stripe function URL: $STRIPE_FUNCTION_URL${NC}"
fi
echo ""

# ── Build env vars string for Cloud Run Job ───────────────────────────────────
JOB_ENV="GOOGLE_CLOUD_PROJECT=$PROJECT_ID"
[ -n "$STRIPE_FUNCTION_URL" ]    && JOB_ENV="$JOB_ENV,STRIPE_FUNCTION_URL=$STRIPE_FUNCTION_URL"
[ -n "$AUTOCARE_API_EMAIL" ]     && JOB_ENV="$JOB_ENV,AUTOCARE_API_EMAIL=$AUTOCARE_API_EMAIL"
[ -n "$AUTOCARE_API_PASSWORD" ]  && JOB_ENV="$JOB_ENV,AUTOCARE_API_PASSWORD=$AUTOCARE_API_PASSWORD"
[ -n "$REPLIT_WEBHOOK_URL" ]     && JOB_ENV="$JOB_ENV,REPLIT_WEBHOOK_URL=$REPLIT_WEBHOOK_URL"
[ -n "$REPLIT_WEBHOOK_SECRET" ]  && JOB_ENV="$JOB_ENV,REPLIT_WEBHOOK_SECRET=$REPLIT_WEBHOOK_SECRET"

# ── Deploy (create or update) Cloud Run Job ───────────────────────────────────
echo -e "${YELLOW}Deploying Cloud Run Job ($JOB_NAME)...${NC}"

DEPLOY_ARGS=(
    --image="$IMAGE"
    --region="$REGION"
    --service-account="$SERVICE_ACCOUNT"
    --memory="$MEMORY"
    --cpu="$CPU"
    --task-timeout="$TIMEOUT"
    --max-retries="$MAX_RETRIES"
    --set-env-vars="$JOB_ENV"
    --project="$PROJECT_ID"
)

if gcloud run jobs describe "$JOB_NAME" --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
    echo "  Updating existing job..."
    gcloud run jobs update "$JOB_NAME" "${DEPLOY_ARGS[@]}"
else
    echo "  Creating new job..."
    gcloud run jobs create "$JOB_NAME" "${DEPLOY_ARGS[@]}"
fi

echo -e "${GREEN}✓ Cloud Run Job deployed${NC}"
echo ""

# ── Cloud Scheduler: trigger the job daily ────────────────────────────────────
# Cloud Run Jobs are triggered via the Run API, not HTTP directly.
JOB_TRIGGER_URL="https://${REGION}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${PROJECT_ID}/jobs/${JOB_NAME}:run"

echo -e "${YELLOW}Configuring Cloud Scheduler ($SCHEDULER_JOB)...${NC}"
echo "  Schedule : $SCHEDULER_SCHEDULE (UTC)"
echo "  Trigger  : $JOB_TRIGGER_URL"
echo ""

SCHEDULER_ARGS=(
    --location="$REGION"
    --schedule="$SCHEDULER_SCHEDULE"
    --uri="$JOB_TRIGGER_URL"
    --message-body="{}"
    --oauth-service-account-email="$SERVICE_ACCOUNT"
    --time-zone="UTC"
    --description="Triggers AutoCare Cloud Run Job daily at 4 AM UTC"
)

if gcloud scheduler jobs describe "$SCHEDULER_JOB" --location="$REGION" --project="$PROJECT_ID" &>/dev/null; then
    echo "  Updating existing scheduler job..."
    gcloud scheduler jobs update http "$SCHEDULER_JOB" "${SCHEDULER_ARGS[@]}" --project="$PROJECT_ID"
else
    echo "  Creating new scheduler job..."
    gcloud scheduler jobs create http "$SCHEDULER_JOB" "${SCHEDULER_ARGS[@]}" --project="$PROJECT_ID"
fi

echo -e "${GREEN}✓ Cloud Scheduler configured${NC}"
echo ""

echo -e "${GREEN}=========================================="
echo "AutoCare Cloud Run Job Deployed!"
echo "==========================================${NC}"
echo ""
echo "  Job name    : $JOB_NAME"
echo "  Image       : $IMAGE"
echo "  Memory      : $MEMORY  |  CPU: $CPU  |  Timeout: $TIMEOUT"
echo "  Schedule    : $SCHEDULER_SCHEDULE UTC (daily)"
echo "  Stripe URL  : ${STRIPE_FUNCTION_URL:-(not set)}"
echo ""
echo "Manual trigger:"
echo "  gcloud run jobs execute $JOB_NAME --region=$REGION --project=$PROJECT_ID"
echo ""
echo "View logs:"
echo "  gcloud run jobs executions list --job=$JOB_NAME --region=$REGION"
echo "  gcloud logging read 'resource.type=cloud_run_job' --limit=100 --project=$PROJECT_ID"
echo ""
echo "Create the 4 staging tables if not already done:"
echo "  ./create-tables.sh"
echo ""
