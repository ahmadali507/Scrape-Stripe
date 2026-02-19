import os
import requests
from typing import List, Dict, Optional
from dotenv import load_dotenv

load_dotenv()

STRIPE_API_KEY = os.getenv('STRIPE_SECRET_KEY')
STRIPE_API_BASE = 'https://api.stripe.com/v1'

if not STRIPE_API_KEY:
    raise ValueError(
        "STRIPE_SECRET_KEY not found in environment variables.\n"
        "Please set it in your .env file or system environment."
    )


def fetch_customers(limit: Optional[int] = None) -> List[Dict]:
    """Fetch customers from Stripe. If limit is None, fetch all (paginated)."""
    all_customers = []
    starting_after = None

    while True:
        try:
            url = f"{STRIPE_API_BASE}/customers"
            headers = {
                'Authorization': f'Bearer {STRIPE_API_KEY}',
                'Content-Type': 'application/x-www-form-urlencoded',
            }
            params = {'limit': 100}
            if starting_after:
                params['starting_after'] = starting_after

            response = requests.get(url, headers=headers, params=params, timeout=30)
            response.raise_for_status()
            data = response.json()
            customers = data.get('data', [])
            all_customers.extend(customers)

            if limit is not None and len(all_customers) >= limit:
                return all_customers[:limit]
            if not data.get('has_more', False) or not customers:
                break
            starting_after = customers[-1]['id']
        except requests.exceptions.RequestException as e:
            print(f"Error fetching customers: {e}")
            break
        except Exception as e:
            print(f"Unexpected error: {e}")
            break

    return all_customers


def fetch_subscriptions_for_customer(customer_id: str, limit: int = 100) -> List[Dict]:
    """Fetch subscriptions for a customer with price.product expanded (to get product_id)."""
    all_subs = []
    starting_after = None
    params = {
        'customer': customer_id,
    }

    while True:
        try:
            if starting_after:
                params['starting_after'] = starting_after
            url = f"{STRIPE_API_BASE}/subscriptions"
            headers = {
                'Authorization': f'Bearer {STRIPE_API_KEY}',
                'Content-Type': 'application/x-www-form-urlencoded',
            }
            response = requests.get(url, headers=headers, params=params, timeout=30)
            response.raise_for_status()
            data = response.json()
            items = data.get('data', [])
            all_subs.extend(items)
            if not data.get('has_more', False) or not items:
                break
            starting_after = items[-1]['id']
        except requests.exceptions.RequestException as e:
            print(f"Error fetching subscriptions for {customer_id}: {e}")
            break
        except Exception as e:
            print(f"Unexpected error: {e}")
            break

    return all_subs


def get_product_ids_from_subscription(subscription: Dict) -> List[str]:
    """Extract product_id(s) from a subscription (price.product can be id or expanded object)."""
    product_ids = []
    for item in subscription.get('items', {}).get('data', []):
        price = item.get('price') or {}
        product = price.get('product')
        if isinstance(product, dict):
            pid = product.get('id')
            if pid:
                product_ids.append(pid)
        elif isinstance(product, str):
            product_ids.append(product)
    return product_ids


def main():
    print("Fetching customers...")
    customers = fetch_customers(limit=10)
    print(f"Fetched {len(customers)} customers.\n")

    for customer in customers:
        cid = customer.get('id')
        if not cid:
            continue
        subs = fetch_subscriptions_for_customer(cid)
        for sub in subs:
            prod_ids = get_product_ids_from_subscription(sub)
            if prod_ids:
                print(f"Customer {cid}  ->  Subscription {sub.get('id')}  ->  product_ids: {prod_ids}")


if __name__ == '__main__':
    main()
