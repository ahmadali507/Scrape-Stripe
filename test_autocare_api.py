import requests
import time

BASE_URL = "https://memberships.autocarepr.com/api"
CREDENTIALS = {"email": "admin_api@autocare.com", "password": "Test1234"}

# Login
login = requests.post(f"{BASE_URL}/login", json=CREDENTIALS)
token = login.json().get("accessToken")
print("Login status:", login.status_code)

# Count all customers across pages (with retry on dropped connections)
headers = {"Authorization": f"Bearer {token}"}
total = 0
page = 1

while True:
    batch = None
    for attempt in range(1, 4):
        try:
            resp = requests.get(
                f"{BASE_URL}/v1/marketing/tiers",
                headers=headers,
                params={"page": page, "per_page": 1000, "includeOnlyServiceType": "true"},
                timeout=60
            )
            batch = resp.json().get("data", [])
            break
        except (requests.exceptions.ChunkedEncodingError, requests.exceptions.ConnectionError) as e:
            print(f"  Page {page} attempt {attempt} failed: {e}. Retrying in 3s...")
            time.sleep(3)

    if batch is None:
        print(f"  Page {page} failed after 3 attempts. Stopping.")
        break

    total += len(batch)
    print(f"Page {page}: {len(batch)} records (running total: {total})")
    if len(batch) < 1000:
        print(f"Page {page} is the last page ({len(batch)} < 1000).")
        break
    page += 1

print(f"\nTotal customers: {total}")
