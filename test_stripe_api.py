import os
import json
import requests
from datetime import datetime
from typing import List, Dict, Optional
from dotenv import load_dotenv

# Load environment variables from .env file
try:
    load_dotenv()
except Exception as e:
    print(f"Warning: Could not load .env file: {e}")

# Stripe API Configuration
STRIPE_API_KEY = os.getenv('STRIPE_SECRET_KEY')
STRIPE_API_BASE = 'https://api.stripe.com/v1'

# Validate API key
if not STRIPE_API_KEY:
    raise ValueError(
        "STRIPE_SECRET_KEY not found in environment variables.\n"
        "Please set it in your .env file or system environment."
    )


def format_timestamp(timestamp: int) -> str:
    """Convert Unix timestamp to readable date string."""
    if timestamp:
        return datetime.fromtimestamp(timestamp).strftime('%Y-%m-%d %H:%M:%S')
    return ''


def fetch_stripe_data(endpoint: str, limit: int = 5) -> Optional[Dict]:
    """
    Fetch data from any Stripe API endpoint.
    
    Args:
        endpoint: The API endpoint (e.g., 'customers', 'subscriptions', 'invoices')
        limit: Number of items to fetch
    
    Returns:
        API response as dictionary or None if error
    """
    try:
        url = f"{STRIPE_API_BASE}/{endpoint}"
        headers = {
            'Authorization': f'Bearer {STRIPE_API_KEY}',
            'Content-Type': 'application/x-www-form-urlencoded'
        }
        params = {'limit': limit}
        
        response = requests.get(url, headers=headers, params=params, timeout=30)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        print(f"  [!] Error fetching {endpoint}: {e}")
        return None
    except Exception as e:
        print(f"  [!] Unexpected error: {e}")
        return None


def print_section_header(title: str):
    """Print a formatted section header."""
    print("\n" + "=" * 80)
    print(f"  {title}")
    print("=" * 80)


def print_data_structure(data: Dict, indent: int = 0, max_depth: int = 3):
    """
    Recursively print the structure of data with types and sample values.
    
    Args:
        data: Dictionary to analyze
        indent: Current indentation level
        max_depth: Maximum depth to traverse
    """
    if indent > max_depth:
        return
    
    prefix = "  " * indent
    
    for key, value in data.items():
        if value is None:
            print(f"{prefix}- {key}: null")
        elif isinstance(value, bool):
            print(f"{prefix}- {key}: (bool) {value}")
        elif isinstance(value, int):
            # Check if it's a timestamp
            if key in ['created', 'updated', 'date', 'period_start', 'period_end', 
                      'current_period_start', 'current_period_end', 'trial_end', 'trial_start']:
                formatted = format_timestamp(value) if value > 0 else 'N/A'
                print(f"{prefix}- {key}: (timestamp) {value} -> {formatted}")
            else:
                print(f"{prefix}- {key}: (int) {value}")
        elif isinstance(value, float):
            print(f"{prefix}- {key}: (float) {value}")
        elif isinstance(value, str):
            # Truncate long strings
            display_value = value if len(value) <= 50 else value[:50] + "..."
            print(f"{prefix}- {key}: (str) '{display_value}'")
        elif isinstance(value, list):
            print(f"{prefix}- {key}: (list) [{len(value)} items]")
            if value and indent < max_depth:
                # Show structure of first item
                if isinstance(value[0], dict):
                    print(f"{prefix}  First item structure:")
                    print_data_structure(value[0], indent + 2, max_depth)
                else:
                    print(f"{prefix}  Sample: {value[0]}")
        elif isinstance(value, dict):
            print(f"{prefix}- {key}: (object)")
            print_data_structure(value, indent + 1, max_depth)
        else:
            print(f"{prefix}- {key}: ({type(value).__name__}) {value}")


def explore_endpoint(endpoint: str, title: str, limit: int = 3):
    """
    Explore a Stripe API endpoint and display available data.
    
    Args:
        endpoint: API endpoint to explore
        title: Display title
        limit: Number of records to fetch
    """
    print_section_header(f"{title} ({endpoint})")
    
    data = fetch_stripe_data(endpoint, limit=limit)
    
    if not data:
        print("  [!] No data retrieved or error occurred")
        return
    
    # Check if it's a list response
    if isinstance(data, dict) and 'data' in data:
        items = data.get('data', [])
        total = len(items)
        has_more = data.get('has_more', False)
        
        print(f"\n  Retrieved: {total} item(s)")
        if has_more:
            print(f"  Note: More items available (showing first {limit})")
        
        if total > 0:
            print(f"\n  --- STRUCTURE OF FIRST {endpoint.upper()} ITEM ---")
            print_data_structure(items[0])
            
            # If there are multiple items, show count
            if total > 1:
                print(f"\n  (... and {total - 1} more item(s) with similar structure)")
        else:
            print("  No items found")
    else:
        print("\n  --- DATA STRUCTURE ---")
        print_data_structure(data)


def explore_single_item(endpoint: str, item_id: str, title: str):
    """
    Explore a single item from Stripe API.
    
    Args:
        endpoint: API endpoint
        item_id: ID of the item to fetch
        title: Display title
    """
    print_section_header(f"{title} (Single Item)")
    
    try:
        url = f"{STRIPE_API_BASE}/{endpoint}/{item_id}"
        headers = {
            'Authorization': f'Bearer {STRIPE_API_KEY}',
            'Content-Type': 'application/x-www-form-urlencoded'
        }
        
        response = requests.get(url, headers=headers, timeout=30)
        response.raise_for_status()
        data = response.json()
        
        print(f"\n  Retrieved {endpoint}: {item_id}")
        print(f"\n  --- DETAILED STRUCTURE ---")
        print_data_structure(data, max_depth=4)
        
    except requests.exceptions.RequestException as e:
        print(f"  [!] Error fetching {endpoint}/{item_id}: {e}")


def get_available_fields_summary(endpoint: str, limit: int = 10) -> Dict:
    """
    Get a summary of all available fields from multiple items.
    
    Args:
        endpoint: API endpoint to explore
        limit: Number of items to analyze
    
    Returns:
        Dictionary with field names and their types
    """
    data = fetch_stripe_data(endpoint, limit=limit)
    
    if not data or 'data' not in data:
        return {}
    
    items = data.get('data', [])
    if not items:
        return {}
    
    # Collect all unique fields across all items
    all_fields = {}
    
    def extract_fields(obj, prefix=""):
        if not isinstance(obj, dict):
            return
        
        for key, value in obj.items():
            field_path = f"{prefix}.{key}" if prefix else key
            
            if field_path not in all_fields:
                all_fields[field_path] = set()
            
            all_fields[field_path].add(type(value).__name__)
            
            # Recursively explore nested objects (limit depth)
            if isinstance(value, dict) and len(prefix.split('.')) < 2:
                extract_fields(value, field_path)
            elif isinstance(value, list) and value and isinstance(value[0], dict):
                extract_fields(value[0], field_path)
    
    for item in items:
        extract_fields(item)
    
    return all_fields


def print_field_summary(endpoint: str, title: str, limit: int = 10):
    """Print a summary of all available fields."""
    print_section_header(f"ALL AVAILABLE FIELDS - {title}")
    
    fields = get_available_fields_summary(endpoint, limit)
    
    if not fields:
        print("  [!] No fields found")
        return
    
    print(f"\n  Total unique fields found: {len(fields)}")
    print(f"\n  Field List (with data types):\n")
    
    for field_name, types in sorted(fields.items()):
        types_str = ", ".join(sorted(types))
        print(f"    - {field_name:40s} -> {types_str}")


def main():
    """
    Main function to explore all Stripe API endpoints.
    """
    print("\n" + "=" * 80)
    print("  STRIPE API DATA EXPLORER")
    print("  Comprehensive Analysis of Available Data")
    print("=" * 80)
    
    # Define all endpoints to explore
    endpoints = [
        ('customers', 'CUSTOMERS'),
        ('subscriptions', 'SUBSCRIPTIONS'),
        ('invoices', 'INVOICES'),
        ('charges', 'CHARGES'),
        ('payment_intents', 'PAYMENT INTENTS'),
        ('products', 'PRODUCTS'),
        ('prices', 'PRICES'),
        ('coupons', 'COUPONS'),
        ('payment_methods', 'PAYMENT METHODS'),
        ('balance_transactions', 'BALANCE TRANSACTIONS'),
        ('refunds', 'REFUNDS'),
        ('disputes', 'DISPUTES'),
        ('payouts', 'PAYOUTS'),
        ('plans', 'PLANS (Legacy)'),
        ('checkout/sessions', 'CHECKOUT SESSIONS'),
    ]
    
    print("\n" + "=" * 80)
    print("PART 1: Quick Overview of All Endpoints")
    print("=" * 80)
    
    # Quick overview
    for endpoint, title in endpoints:
        print(f"\n  Testing: {title}...", end=" ")
        data = fetch_stripe_data(endpoint, limit=1)
        if data and 'data' in data:
            count = len(data.get('data', []))
            has_more = data.get('has_more', False)
            if count > 0:
                print(f"[OK] Available ({count} sample{'s' if count > 1 else ''}{', more available' if has_more else ''})")
            else:
                print("[OK] Endpoint accessible (no data yet)")
        elif data:
            print("[OK] Available")
        else:
            print("[!] Not accessible or error")
    
    print("\n\n" + "=" * 80)
    print("PART 2: Detailed Structure Analysis")
    print("=" * 80)
    print("  Analyzing top endpoints with sample data...")
    
    # Detailed exploration of main endpoints
    main_endpoints = [
        ('customers', 'CUSTOMERS'),
        ('subscriptions', 'SUBSCRIPTIONS'),
        ('invoices', 'INVOICES'),
        ('charges', 'CHARGES'),
        ('products', 'PRODUCTS'),
        ('prices', 'PRICES'),
    ]
    
    for endpoint, title in main_endpoints:
        explore_endpoint(endpoint, title, limit=2)
    
    print("\n\n" + "=" * 80)
    print("PART 3: Complete Field Lists")
    print("=" * 80)
    print("  Generating comprehensive field lists...")
    
    # Field summaries
    for endpoint, title in main_endpoints:
        print_field_summary(endpoint, title, limit=20)
    
    print("\n\n" + "=" * 80)
    print("EXPLORATION COMPLETE!")
    print("=" * 80)
    print("\nTIPS:")
    print("  - Use the field lists above to understand what data is available")
    print("  - Nested fields are shown with dot notation (e.g., 'metadata.key')")
    print("  - Timestamps are Unix timestamps (convert with format_timestamp function)")
    print("  - Check the Stripe API docs for detailed field descriptions:")
    print("    https://stripe.com/docs/api")
    print("\n" + "=" * 80)


if __name__ == '__main__':
    main()

