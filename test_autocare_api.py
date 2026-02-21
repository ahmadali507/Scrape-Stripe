import requests
import json

# --- CONFIGURATION ---
BASE_URL = "https://autocare-memberships-832d3.ondigitalocean.app/api"

LOGIN_URL = f"{BASE_URL}/login"
TIERS_URL = f"{BASE_URL}/v1/marketing/tiers"
DATA_URL = f"{BASE_URL}/v1/marketing/data"

CREDENTIALS = {
    "email": "api_admin@test.com",
    "password": "Test11234"
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
        data_list = marketing_data.get("data", []) if isinstance(marketing_data, dict) else marketing_data
        max_show = 15
        if len(data_list) > max_show:
            truncated = {**marketing_data, "data": data_list[:max_show]}
            print("Raw response (marketing data, first %d of %d):" % (max_show, len(data_list)))
            print(json.dumps(truncated, indent=2))
            print("... and %d more records." % (len(data_list) - max_show))
        else:
            print("Raw response (marketing data):")
            print(json.dumps(marketing_data, indent=2))
        analyze_marketing_data(marketing_data)

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

def analyze_marketing_data(data):
    """Summarize structure and content of marketing data response."""
    print("\n--- Marketing data analysis ---")
    if isinstance(data, list):
        print(f"Type: list with {len(data)} item(s)")
        for i, item in enumerate(data[:5]):  # first 5
            if isinstance(item, dict):
                print(f"  Item {i}: keys = {list(item.keys())}")
            else:
                print(f"  Item {i}: {type(item).__name__}")
        if len(data) > 5:
            print(f"  ... and {len(data) - 5} more")
    elif isinstance(data, dict):
        print(f"Type: dict with keys: {list(data.keys())}")
        for k, v in data.items():
            if isinstance(v, list):
                print(f"  '{k}': list of {len(v)} item(s)")
            elif isinstance(v, dict):
                print(f"  '{k}': dict with keys {list(v.keys())[:8]}{'...' if len(v) > 8 else ''}")
            else:
                print(f"  '{k}': {type(v).__name__}")
    else:
        print(f"Type: {type(data).__name__}")

if __name__ == "__main__":
    main()
