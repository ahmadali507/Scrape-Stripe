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

# AutoCare datasets and tables (Stripe + AutoCare pipeline)
echo -e "${YELLOW}Creating AutoCare datasets (if not exist)...${NC}"
bq mk -d autocare_raw 2>/dev/null || true
bq mk -d autocare_processed 2>/dev/null || true
bq mk -d autocare_metadata 2>/dev/null || true
echo -e "${YELLOW}Creating AutoCare raw tables...${NC}"
bq query --use_legacy_sql=false < "$SQL_DIR/create_autocare_raw_tables.sql"
echo -e "${YELLOW}Creating AutoCare processed tables...${NC}"
bq query --use_legacy_sql=false < "$SQL_DIR/create_autocare_processed_tables.sql"
echo -e "${YELLOW}Creating AutoCare metadata tables...${NC}"
bq query --use_legacy_sql=false < "$SQL_DIR/create_autocare_metadata_tables.sql"
echo -e "${GREEN}✓ AutoCare tables created${NC}"
echo ""

# Unified and BI datasets (used by Cloud Function after sync; tables populated on first sync)
echo -e "${YELLOW}Creating unified and bi datasets (if not exist)...${NC}"
bq mk -d unified 2>/dev/null || true
bq mk -d bi 2>/dev/null || true
echo -e "${GREEN}✓ unified, bi datasets ready${NC}"
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
echo "  unified: (customers table populated by Cloud Function from view)"
echo "  bi: (unified_customer_360_snapshot populated by Cloud Function)"
echo "  autocare_raw: tiers_raw, marketing_data_raw"
echo "  autocare_processed: tiers, marketing_customers, marketing_subscriptions, marketing_sessions, marketing_cars"
echo "  autocare_metadata: sync_history"
echo ""
echo "To create unified_customers view (required before first sync with unified/BI):"
echo "  1. Replace PROJECT_ID in sql/create_unified_customer_view.sql with $PROJECT_ID"
echo "  2. bq query --use_legacy_sql=false < sql/create_unified_customer_view.sql"
echo ""
echo "Unified table (unified.customers) and BI table (bi.unified_customer_360_snapshot) are"
echo "refreshed automatically by the Cloud Function after each Stripe + AutoCare sync."
echo ""

