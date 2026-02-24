import requests
import json

# --- CONFIGURATION ---
BASE_URL = "https://autocare-memberships-832d3.ondigitalocean.app/api"

LOGIN_URL = f"{BASE_URL}/login"
TIERS_URL = f"{BASE_URL}/v1/marketing/tiers"
DATA_URL = f"{BASE_URL}/v1/marketing/data"

CREDENTIALS = {
    "email": "api_admin@test.com",
    "password": "Test1234"
}

# --- EXECUTION ---

def get_jwt_token():
    """Login and return JWT token from response."""
    print(f"Attempting login to: {LOGIN_URL}...")
    resp = requests.post(LOGIN_URL, json=CREDENTIALS)
    if resp.status_code not in [200, 201]:
        print(f"Login failed. Status: {resp.status_code}")
        print("Response:", resp.text[:500])
        return None
    data = resp.json()
    # Common JWT response keys
    token = data.get("token") or data.get("access_token") or data.get("accessToken") or data.get("jwt")
    if not token:
        print("Login response (no token found):", json.dumps(data, indent=2))
        return None
    print("Login successful. JWT token obtained.")
    return token

def fetch_with_auth(url, token):
    """GET url with Bearer token in Authorization header."""
    headers = {"Authorization": f"Bearer {token}"}
    resp = requests.get(url, headers=headers)
    return resp

def main():
    token = get_jwt_token()
    if not token:
        return

    # --- v1/marketing/tiers ---
    print(f"\n{'='*60}")
    print(f"GET {TIERS_URL}")
    print("="*60)
    tiers_resp = fetch_with_auth(TIERS_URL, token)
    if tiers_resp.status_code != 200:
        print(f"Tiers request failed. Status: {tiers_resp.status_code}")
        print("Response:", tiers_resp.text[:500])
    else:
        tiers_data = tiers_resp.json()
        print("Raw response (tiers):")
        print(json.dumps(tiers_data, indent=2))
        analyze_tiers(tiers_data)

    # --- v1/marketing/data ---
    print(f"\n{'='*60}")
    print(f"GET {DATA_URL}")
    print("="*60)
    data_resp = fetch_with_auth(DATA_URL, token)
    if data_resp.status_code != 200:
        print(f"Data request failed. Status: {data_resp.status_code}")
        print("Response:", data_resp.text[:500])
    else:
        marketing_data = data_resp.json()
        records = get_records(marketing_data)
        emails = [r.get("email") for r in records if isinstance(r, dict)]
        total = len(records)
        print(f"Total record count: {total}")
        print("\nCustomer emails:")
        for i, email in enumerate(emails, 1):
            print(f"  {i}. {email or '(empty)'}")

def get_records(data):
    """Return the data array from marketing API response."""
    if isinstance(data, dict) and "data" in data:
        return data["data"] if isinstance(data["data"], list) else []
    if isinstance(data, list):
        return data
    return []

def count_customers(data):
    """
    Return total number of customers from marketing API response.
    Expects { "success", "count", "data": [ ... ] }; each item in data is a customer record.
    """
        return len(get_records(data))

def analyze_tiers(data):
    """Summarize structure and content of tiers response."""
    print("\n--- Tiers analysis ---")
    if isinstance(data, list):
        print(f"Type: list with {len(data)} item(s)")
        for i, item in enumerate(data):
            if isinstance(item, dict):
                print(f"  Item {i}: keys = {list(item.keys())}")
            else:
                print(f"  Item {i}: {type(item).__name__} = {item}")
    elif isinstance(data, dict):
        print(f"Type: dict with keys: {list(data.keys())}")
        for k, v in data.items():
            if isinstance(v, list):
                print(f"  '{k}': list of {len(v)} item(s)")
            else:
                print(f"  '{k}': {type(v).__name__}")
    else:
        print(f"Type: {type(data).__name__}")

if __name__ == "__main__":
    main()
