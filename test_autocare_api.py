import requests

# --- CONFIGURATION ---
BASE_URL = "https://autocare-memberships-832d3.ondigitalocean.app/api"

# 1. SETUP: Define the specific endpoints
# You must check your Swagger docs for the exact Login path (e.g., /auth/login, /users/login)
LOGIN_URL = f"{BASE_URL}/login" 
HISTORY_URL = f"{BASE_URL}/getUserData"

# 2. CREDENTIALS
payload = {
    "email": "api_admin@test.com",  # Replace with actual email
    "password": "Test1234"         # Replace with actual password
}

# --- EXECUTION ---

# 3. START SESSION
# The 'session' object persists cookies across requests, just like a browser.
session = requests.Session()

print(f"Attempting login to: {LOGIN_URL}...")

# 4. LOGIN
try:
    login_response = session.post(LOGIN_URL, json=payload)
    
    # Check if login was successful (usually 200 or 201)
    if login_response.status_code in [200, 201]:
        print("Login Successful!")
        print(f"Cookies received: {session.cookies.get_dict()}")
        
        # 5. GET HISTORY DATA - using session cookies (cookie-based auth)
        params = {"limit": 10, "page": 1}
        
        print(f"\nQuerying History Data from: {HISTORY_URL}...")
        history_response = session.get(HISTORY_URL, params=params)
        
        if history_response.status_code == 200:
            # Handle both JSON and non-JSON responses
            content_type = history_response.headers.get("Content-Type", "")
            if "application/json" in content_type:
                data = history_response.json()
                print("Data Retrieved Successfully:")
                print(data)
            else:
                print("Response is not JSON (got HTML or other format).")
                print("Preview:", history_response.text[:300] + "..." if len(history_response.text) > 300 else history_response.text)
        else:
            print(f"Failed to get history. Status: {history_response.status_code}")
            print("Response:", history_response.text[:500])
            
    else:
        print(f"Login Failed. Status: {login_response.status_code}")
        print("Response:", login_response.text)

except Exception as e:
    print(f"An error occurred: {e}")