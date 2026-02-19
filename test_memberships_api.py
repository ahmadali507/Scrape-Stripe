import requests
import json
from datetime import datetime
from typing import List, Dict, Optional

# --- CONFIGURATION ---
BASE_URL = "https://autocare-memberships-832d3.ondigitalocean.app"
API_BASE_URL = f"{BASE_URL}/api"
LOGIN_URL = f"{API_BASE_URL}/login"  # Based on Postman collection: /api/login

# Login credentials
LOGIN_PAYLOAD = {
    "email": "api_user@test.com",
    "password": "Test1234"
}

# Sample customer IDs to test (including the one from your example + some from the JSON file)
TEST_CUSTOMER_IDS = [
    "cus_SNp9DTt6p1SiqQ",  # From your example
    "cus_TpJsFXwi2nYSzH",  # Maria Rivera
    "cus_TozunmdX8wI73x",  # David Baerga
    "cus_TnW4iBNAaDifnA",  # Luis Irizarry
    "cus_TmnTaIc7wrpuKE",  # Sofia Donatelli
    "cus_TmPP3VDvTOEPnP",  # Daria Perez
    "cus_Tlx5i7JetQlIIr",  # Raiza Rijos
    "cus_Tlf5F3QkYmlHaR",  # Taina Rodriguez
    "cus_TlE1aObQozq7na",  # Neribel Torres Estrada
    "cus_TksOkM7WDBma3H",  # Amarys Vellise Bolorín Soliván
]


def load_customer_ids_from_json(filename: str = "customer_phone_analysis_20260121_165649.json", max_count: int = 50) -> List[str]:
    """
    Load customer IDs from the JSON file.
    
    Args:
        filename: JSON file containing customer data
        max_count: Maximum number of customer IDs to load
    
    Returns:
        List of customer IDs
    """
    try:
        with open(filename, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        customer_ids = []
        
        # Get customers with phone numbers
        if 'customers_with_phone' in data:
            for customer in data['customers_with_phone'][:max_count//2]:
                if 'id' in customer:
                    customer_ids.append(customer['id'])
        
        # Get customers without phone numbers
        if 'customers_without_phone' in data and len(customer_ids) < max_count:
            remaining = max_count - len(customer_ids)
            for customer in data['customers_without_phone'][:remaining]:
                if 'id' in customer:
                    customer_ids.append(customer['id'])
        
        return customer_ids
    except FileNotFoundError:
        print(f"  [!] Warning: {filename} not found, using default customer IDs only")
        return []
    except Exception as e:
        print(f"  [!] Warning: Could not load {filename}: {e}")
        return []


def print_header(title: str):
    """Print a formatted header."""
    print("\n" + "=" * 100)
    print(f"  {title}")
    print("=" * 100)


def login_and_get_token() -> Optional[str]:
    """
    Login to the API and retrieve the JWT token.
    
    Returns:
        JWT token string or None if login fails
    """
    print_header("STEP 1: LOGIN TO API")
    
    print(f"\n  Attempting login to: {LOGIN_URL}")
    print(f"  Email: {LOGIN_PAYLOAD['email']}")
    
    try:
        response = requests.post(LOGIN_URL, json=LOGIN_PAYLOAD, timeout=30)
        
        print(f"  Status Code: {response.status_code}")
        
        if response.status_code in [200, 201]:
            # Try to parse JSON response
            try:
                data = response.json()
                print(f"\n  [OK] Login Successful!")
                print(f"\n  Response data:")
                print(json.dumps(data, indent=2))
                
                # Extract token (could be in various fields)
                token = None
                if 'accessToken' in data:
                    token = data['accessToken']
                elif 'token' in data:
                    token = data['token']
                elif 'access_token' in data:
                    token = data['access_token']
                
                if token:
                    print(f"\n  [OK] JWT Token retrieved successfully")
                    print(f"  Token preview: {token[:50]}..." if len(token) > 50 else f"  Token: {token}")
                    return token
                else:
                    print("\n  [!] Warning: Login successful but no token found in response")
                    print(f"  Available keys: {list(data.keys())}")
                    return None
                    
            except json.JSONDecodeError:
                print(f"\n  [!] Login response is not JSON")
                print(f"  Response text: {response.text[:500]}")
                return None
        else:
            print(f"\n  [!] Login Failed!")
            print(f"  Response: {response.text[:500]}")
            return None
            
    except requests.exceptions.RequestException as e:
        print(f"\n  [!] Error during login: {e}")
        return None


def test_customer_memberships(customer_id: str, token: str) -> Dict:
    """
    Test the memberships endpoint for a specific customer.
    
    Args:
        customer_id: Stripe customer ID
        token: JWT authentication token
    
    Returns:
        Dictionary with test results
    """
    url = f"{API_BASE_URL}/v1/customers/{customer_id}/memberships"
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json'
    }
    
    result = {
        'customer_id': customer_id,
        'url': url,
        'success': False,
        'status_code': None,
        'has_data': False,
        'data': None,
        'error': None
    }
    
    try:
        response = requests.get(url, headers=headers, timeout=30)
        result['status_code'] = response.status_code
        
        if response.status_code == 200:
            result['success'] = True
            try:
                data = response.json()
                result['data'] = data
                
                # Check if data exists (various possible structures)
                if isinstance(data, dict):
                    if 'data' in data and data['data']:
                        result['has_data'] = True
                    elif 'memberships' in data and data['memberships']:
                        result['has_data'] = True
                    elif len(data) > 0 and any(v for v in data.values() if v):
                        result['has_data'] = True
                elif isinstance(data, list) and len(data) > 0:
                    result['has_data'] = True
                    
            except json.JSONDecodeError:
                result['error'] = "Response is not valid JSON"
                result['data'] = response.text[:200]
        elif response.status_code == 404:
            result['error'] = "Customer not found or no memberships"
            try:
                result['data'] = response.json()
            except:
                result['data'] = response.text[:500] if response.text else None
        elif response.status_code == 401:
            result['error'] = "Unauthorized - token may be invalid"
            try:
                result['data'] = response.json()
            except:
                result['data'] = response.text[:500] if response.text else None
        elif response.status_code == 403:
            result['error'] = "Forbidden - insufficient permissions"
            try:
                result['data'] = response.json()
            except:
                result['data'] = response.text[:500] if response.text else None
        else:
            result['error'] = f"HTTP {response.status_code}"
            try:
                result['data'] = response.json()
            except:
                result['data'] = response.text[:500] if response.text else None
                
    except requests.exceptions.RequestException as e:
        result['error'] = str(e)
    
    return result


def test_all_customers(token: str, customer_ids: List[str]) -> List[Dict]:
    """
    Test the memberships endpoint for multiple customers.
    
    Args:
        token: JWT authentication token
        customer_ids: List of customer IDs to test
    
    Returns:
        List of test results
    """
    print_header("STEP 2: TESTING CUSTOMER MEMBERSHIPS ENDPOINT")
    
    print(f"\n  Testing {len(customer_ids)} customer IDs...")
    print(f"  Base URL: {API_BASE_URL}/v1/customers/{{customer_id}}/memberships")
    print()
    
    results = []
    customers_with_data = []
    customers_without_data = []
    customers_with_errors = []
    
    for i, customer_id in enumerate(customer_ids, 1):
        print(f"\n  [{i}/{len(customer_ids)}] Testing: {customer_id}")
        result = test_customer_memberships(customer_id, token)
        results.append(result)
        
        # Categorize results
        if result['success']:
            if result['has_data']:
                customers_with_data.append(customer_id)
                print(f"       Status: [OK] SUCCESS - Has membership data *** FOUND DATA ***")
            else:
                customers_without_data.append(customer_id)
                print(f"       Status: [OK] OK - No membership data (empty response)")
        else:
            customers_with_errors.append(customer_id)
            # Only show first few errors to avoid cluttering output
            if i <= 5 or result['status_code'] != 404:
                print(f"       Status: [ERROR] {result['error']}")
                if result['data']:
                    print(f"       Response: {result['data']}")
            else:
                print(f"       Status: [ERROR] {result['error']}")
    
    # Print summary
    print_header("STEP 3: RESULTS SUMMARY")
    
    print(f"\n  Total Customers Tested: {len(customer_ids)}")
    print(f"  Customers WITH Membership Data: {len(customers_with_data)}")
    print(f"  Customers WITHOUT Membership Data: {len(customers_without_data)}")
    print(f"  Customers with Errors: {len(customers_with_errors)}")
    
    # Show customers with data
    if customers_with_data:
        print("\n" + "-" * 100)
        print("  [SUCCESS] CUSTOMERS WITH MEMBERSHIP DATA:")
        print("-" * 100)
        for customer_id in customers_with_data:
            result = next(r for r in results if r['customer_id'] == customer_id)
            print(f"\n  Customer ID: {customer_id}")
            print(f"  Data Preview:")
            print(json.dumps(result['data'], indent=4))
    else:
        print("\n  [!] No customers found with membership data")
    
    # Show sample of customers without data
    if customers_without_data:
        print("\n" + "-" * 100)
        print(f"  [INFO] CUSTOMERS WITHOUT MEMBERSHIP DATA ({len(customers_without_data)} total):")
        print("-" * 100)
        for customer_id in customers_without_data[:5]:
            print(f"    - {customer_id}")
        if len(customers_without_data) > 5:
            print(f"    ... and {len(customers_without_data) - 5} more")
    
    # Show errors
    if customers_with_errors:
        print("\n" + "-" * 100)
        print("  [ERROR] CUSTOMERS WITH ERRORS:")
        print("-" * 100)
        for customer_id in customers_with_errors:
            result = next(r for r in results if r['customer_id'] == customer_id)
            print(f"\n  Customer ID: {customer_id}")
            print(f"  Error: {result['error']}")
            if result['data']:
                print(f"  Response: {result['data']}")
    
    return results


def save_results_to_file(results: List[Dict]):
    """Save test results to a JSON file."""
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    filename = f"memberships_api_test_results_{timestamp}.json"
    
    report = {
        'test_date': datetime.now().isoformat(),
        'total_tested': len(results),
        'results': results,
        'summary': {
            'with_data': len([r for r in results if r['has_data']]),
            'without_data': len([r for r in results if r['success'] and not r['has_data']]),
            'errors': len([r for r in results if not r['success']])
        }
    }
    
    try:
        with open(filename, 'w', encoding='utf-8') as f:
            json.dump(report, f, indent=2, ensure_ascii=False)
        print(f"\n  [OK] Test results saved to: {filename}")
    except Exception as e:
        print(f"\n  [!] Could not save results: {e}")


def main():
    """Main function to run the membership API tests."""
    print("\n" + "=" * 100)
    print("  AUTOCARE MEMBERSHIPS API TESTER")
    print("  Testing Customer Memberships Endpoint with JWT Authentication")
    print("=" * 100)
    
    # Step 1: Login and get token
    token = login_and_get_token()
    
    if not token:
        print("\n  [!] Cannot proceed without authentication token")
        print("  Please check your credentials and try again")
        return
    
    # Load additional customer IDs from JSON file
    print_header("STEP 1.5: LOADING CUSTOMER IDS")
    additional_ids = load_customer_ids_from_json(max_count=200)  # Increased to 200
    
    if additional_ids:
        print(f"\n  [OK] Loaded {len(additional_ids)} customer IDs from JSON file")
        # Combine with default test IDs, removing duplicates
        all_customer_ids = TEST_CUSTOMER_IDS + [cid for cid in additional_ids if cid not in TEST_CUSTOMER_IDS]
        print(f"  Total customer IDs to test: {len(all_customer_ids)}")
    else:
        print(f"\n  [INFO] Using default {len(TEST_CUSTOMER_IDS)} customer IDs only")
        all_customer_ids = TEST_CUSTOMER_IDS
    
    # Step 2: Test customer memberships endpoint
    results = test_all_customers(token, all_customer_ids)
    
    # Step 3: Save results
    print_header("STEP 4: SAVING RESULTS")
    save_results_to_file(results)
    
    print("\n" + "=" * 100)
    print("  TEST COMPLETE!")
    print("=" * 100 + "\n")


if __name__ == '__main__':
    main()
