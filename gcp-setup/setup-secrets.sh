#!/bin/bash
# Script to store Stripe API key in Google Secret Manager

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "Secret Manager Setup"
echo "=========================================="
echo ""

PROJECT_ID=$(gcloud config get-value project)

if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}Error: No GCP project selected${NC}"
    exit 1
fi

echo -e "${YELLOW}Project: $PROJECT_ID${NC}"
echo ""

# Prompt for Stripe API key
echo -e "${YELLOW}Please enter your Stripe Secret Key:${NC}"
echo "(It should start with sk_test_ or sk_live_)"
read -s STRIPE_API_KEY

if [ -z "$STRIPE_API_KEY" ]; then
    echo -e "${RED}Error: No API key provided${NC}"
    exit 1
fi

# Validate key format
if [[ ! $STRIPE_API_KEY =~ ^sk_(test|live)_ ]]; then
    echo -e "${RED}Error: Invalid Stripe API key format${NC}"
    echo "Key should start with sk_test_ or sk_live_"
    exit 1
fi

echo ""
echo -e "${YELLOW}Creating secret in Secret Manager...${NC}"

# Check if secret already exists
if gcloud secrets describe stripe-api-key &>/dev/null; then
    echo -e "${YELLOW}Secret already exists. Adding new version...${NC}"
    echo -n "$STRIPE_API_KEY" | gcloud secrets versions add stripe-api-key --data-file=-
else
    # Create new secret
    echo -n "$STRIPE_API_KEY" | gcloud secrets create stripe-api-key \
        --data-file=- \
        --replication-policy="automatic" \
        --labels="purpose=stripe-sync"
fi

echo -e "${GREEN}✓ Secret stored successfully${NC}"
echo ""

# Grant access to service account
SERVICE_ACCOUNT_EMAIL="stripe-sync-sa@${PROJECT_ID}.iam.gserviceaccount.com"

echo -e "${YELLOW}Granting access to service account...${NC}"
gcloud secrets add-iam-policy-binding stripe-api-key \
    --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
    --role="roles/secretmanager.secretAccessor"

echo -e "${GREEN}✓ Service account granted access to secret${NC}"
echo ""
echo -e "${GREEN}=========================================="
echo "Secret Manager Setup Complete!"
echo "==========================================${NC}"
echo ""
echo "Secret: stripe-api-key"
echo "Service Account: $SERVICE_ACCOUNT_EMAIL"
echo ""

