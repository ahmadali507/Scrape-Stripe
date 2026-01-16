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

# Check if secret already exists in Secret Manager
echo -e "${YELLOW}Checking if Stripe API key secret exists...${NC}"

if gcloud secrets describe stripe-api-key &>/dev/null; then
    echo -e "${GREEN}✓ Secret 'stripe-api-key' already exists in Secret Manager${NC}"
    echo ""
    
    # Get secret metadata
    CREATED=$(gcloud secrets describe stripe-api-key --format='value(createTime)')
    echo "Secret details:"
    echo "  Name: stripe-api-key"
    echo "  Created: $CREATED"
    echo ""
    
    # Ask if user wants to update
    read -p "Do you want to update the existing secret with a new API key? (y/N) " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Using existing secret. Skipping update.${NC}"
        SKIP_UPDATE=true
    else
        SKIP_UPDATE=false
    fi
else
    echo -e "${YELLOW}Secret not found. Will create new secret.${NC}"
    echo ""
    SKIP_UPDATE=false
fi

# Prompt for API key only if needed
if [ "$SKIP_UPDATE" != "true" ]; then
    echo -e "${YELLOW}Please enter your Stripe Secret Key:${NC}"
    echo "(It should start with sk_test_ or sk_live_)"
    echo ""
    echo -e "${YELLOW}Note: Input will be visible. Press Enter after pasting.${NC}"
    read -r STRIPE_API_KEY
    
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
    echo -e "${YELLOW}Storing secret in Secret Manager...${NC}"
    
    # Check if secret exists (again, in case of race condition)
    if gcloud secrets describe stripe-api-key &>/dev/null; then
        echo -e "${YELLOW}Adding new version to existing secret...${NC}"
        echo -n "$STRIPE_API_KEY" | gcloud secrets versions add stripe-api-key --data-file=-
    else
        echo -e "${YELLOW}Creating new secret...${NC}"
        echo -n "$STRIPE_API_KEY" | gcloud secrets create stripe-api-key \
            --data-file=- \
            --replication-policy="automatic" \
            --labels="purpose=stripe-sync"
    fi
    
    echo -e "${GREEN}✓ Secret stored successfully${NC}"
    echo ""
fi

# Ensure service account has access
SERVICE_ACCOUNT_EMAIL="stripe-sync-sa@${PROJECT_ID}.iam.gserviceaccount.com"

echo -e "${YELLOW}Verifying service account access...${NC}"

# Check if service account already has access
EXISTING_BINDING=$(gcloud secrets get-iam-policy stripe-api-key \
    --flatten="bindings[].members" \
    --format="table(bindings.role)" \
    --filter="bindings.members:serviceAccount:$SERVICE_ACCOUNT_EMAIL AND bindings.role:roles/secretmanager.secretAccessor" 2>/dev/null || echo "")

if [ -z "$EXISTING_BINDING" ]; then
    echo -e "${YELLOW}Granting access to service account...${NC}"
    gcloud secrets add-iam-policy-binding stripe-api-key \
        --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
        --role="roles/secretmanager.secretAccessor"
    echo -e "${GREEN}✓ Service account granted access to secret${NC}"
else
    echo -e "${GREEN}✓ Service account already has access to secret${NC}"
fi

echo ""
echo -e "${GREEN}=========================================="
echo "Secret Manager Setup Complete!"
echo "==========================================${NC}"
echo ""
echo "Secret: stripe-api-key"
echo "Service Account: $SERVICE_ACCOUNT_EMAIL"
echo ""

# Verify the secret is accessible
echo -e "${YELLOW}Testing secret access...${NC}"
if gcloud secrets versions access latest --secret=stripe-api-key &>/dev/null; then
    echo -e "${GREEN}✓ Secret is accessible and can be read${NC}"
else
    echo -e "${RED}✗ Warning: Could not access secret${NC}"
fi
echo ""

