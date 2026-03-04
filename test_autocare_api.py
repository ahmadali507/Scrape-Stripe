"""
Test script for the AutoCare marketing API.

Uses the Stripe-linked customers endpoint to avoid scanning the full dataset:
  GET /api/v1/marketing/stripe-customers

- JWT auth (same login); requires API_ADMIN role.
- Cursor-based pagination: limit (default 100, max 1000), cursor from nextCursor.
- Optional: includeOnlyServiceType=true to filter by history type 'Service'.
"""
import json
import requests
import time

BASE_URL = "https://memberships.autocarepr.com/api"
STRIPE_CUSTOMERS_URL = f"{BASE_URL}/v1/marketing/stripe-customers"

# Params per API docs: limit (max 1000), cursor (from nextCursor), includeOnlyServiceType (optional)
LIMIT = 1000

# Use credentials with API_ADMIN role (required for this endpoint)
CREDENTIALS = {"email": "admin_api@autocare.com", "password": "Test1234"}

# Login
print("Logging in...")
login = requests.post(f"{BASE_URL}/login", json=CREDENTIALS)
if login.status_code not in (200, 201):
    print("Login failed:", login.status_code, login.text[:500])
    exit(1)

token = (
    login.json().get("accessToken")
    or login.json().get("access_token")
    or login.json().get("token")
    or login.json().get("jwt")
)
if not token:
    print("Login response had no token")
    exit(1)
print("Login OK\n")

headers = {"Authorization": f"Bearer {token}"}
total = 0
cursor = None
page_num = 0
first_ten_printed = False

while True:
    batch = None
    params = {"limit": LIMIT}
    if cursor:
        params["cursor"] = cursor

    for attempt in range(1, 4):
        try:
            resp = requests.get(
                STRIPE_CUSTOMERS_URL,
                headers=headers,
                params=params,
                timeout=60,
            )
            if resp.status_code == 401:
                print(f"  401 Unauthorized (attempt {attempt}) — token may have expired or missing API_ADMIN role")
                if attempt == 3:
                    print("  Stopping.")
                    exit(1)
                time.sleep(3)
                continue
            resp.raise_for_status()
            data = resp.json()
            # API returns data array and nextCursor for next page
            batch = data.get("data")
            if batch is None and isinstance(data, list):
                batch = data
            if not isinstance(batch, list):
                batch = []
            cursor = data.get("nextCursor")
            break
        except (requests.exceptions.ChunkedEncodingError, requests.exceptions.ConnectionError, requests.exceptions.Timeout) as e:
            print(f"  Attempt {attempt} failed: {e}. Retrying in 3s...")
            time.sleep(3)

    if batch is None:
        print("  Request failed after 3 attempts. Stopping.")
        break

    page_num += 1
    total += len(batch)
    print(f"Page {page_num}: {len(batch)} records (running total: {total})")

    # Print first 10 customers once to show associated fields
    if not first_ten_printed and len(batch) > 0:
        first_ten = batch[:10]
        print("\n--- First 10 customers (field structure) ---")
        for i, customer in enumerate(first_ten, 1):
            print(f"\n  Customer {i}:")
            print(json.dumps(customer, indent=4, default=str))
        print("\n--- Pagination continues ---\n")
        first_ten_printed = True

    if not cursor:
        print("  No nextCursor — done.")
        break
    if len(batch) < LIMIT:
        print("  Last page (short batch).")
        break

print(f"\nTotal Stripe-linked customers: {total}")
