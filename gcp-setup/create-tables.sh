#!/bin/bash
# Script to create all BigQuery tables for Stripe pipeline

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "BigQuery Tables Creation"
echo "=========================================="
echo ""

PROJECT_ID=$(gcloud config get-value project)

if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}Error: No GCP project selected${NC}"
    exit 1
fi

echo -e "${YELLOW}Project: $PROJECT_ID${NC}"
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SQL_DIR="$SCRIPT_DIR/../sql"

# Execute SQL files
echo -e "${YELLOW}Creating metadata tables...${NC}"
bq query --use_legacy_sql=false < "$SQL_DIR/create_metadata_tables.sql"
echo -e "${GREEN}✓ Metadata tables created${NC}"
echo ""

echo -e "${YELLOW}Creating raw data tables...${NC}"
bq query --use_legacy_sql=false < "$SQL_DIR/create_raw_tables.sql"
echo -e "${GREEN}✓ Raw data tables created${NC}"
echo ""

echo -e "${YELLOW}Creating processed tables...${NC}"
bq query --use_legacy_sql=false < "$SQL_DIR/create_processed_tables.sql"
echo -e "${GREEN}✓ Processed tables created${NC}"
echo ""

echo -e "${GREEN}=========================================="
echo "All BigQuery Tables Created!"
echo "==========================================${NC}"
echo ""
echo "Tables created:"
echo "  stripe_metadata:"
echo "    - sync_history"
echo "  stripe_raw:"
echo "    - customers_raw"
echo "    - subscriptions_raw"
echo "  stripe_processed:"
echo "    - customers"
echo "    - subscriptions"
echo ""

