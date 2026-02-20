#!/bin/bash
# Test the Replit /api/webhooks/new-customers endpoint with a sample payload.
# Usage:
#   REPLIT_WEBHOOK_SECRET=xiomara-big-query-secret ./scripts/test_replit_webhook.sh
#   Or: export REPLIT_WEBHOOK_SECRET=... then ./scripts/test_replit_webhook.sh

set -e

REPLIT_URL="${REPLIT_WEBHOOK_URL:-https://data-whisperer--samuel447.replit.app/api/webhooks/new-customers}"
SECRET="${REPLIT_WEBHOOK_SECRET:-}"

if [ -z "$SECRET" ]; then
    echo "Error: Set REPLIT_WEBHOOK_SECRET (same value as on Replit)."
    echo "  export REPLIT_WEBHOOK_SECRET=xiomara-big-query-secret"
    exit 1
fi

echo "POST $REPLIT_URL"
echo "Payload: 1 test customer with product_id"
echo ""

curl -s -w "\n\nHTTP Status: %{http_code}\n" -X POST "$REPLIT_URL" \
  -H "Content-Type: application/json" \
  -H "x-webhook-secret: $SECRET" \
  -H "Authorization: Bearer $SECRET" \
  -d '{
  "customers": [
    {
      "customer_id": "cus_test123",
      "email": "test@example.com",
      "name": "Test User",
      "phone": "+15551234567",
      "product_id": "prod_LQjx67EvzQ1PGQ"
    }
  ],
  "tags": []
}'

echo ""
echo "200 = success; 401 = wrong secret; 4xx/5xx = check Replit."
