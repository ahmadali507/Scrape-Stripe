import os
import time
import requests
from dotenv import load_dotenv

load_dotenv()

# ---------------------------------------------------------------------------
# Stripe
# ---------------------------------------------------------------------------

STRIPE_API_KEY = os.getenv("STRIPE_SECRET_KEY")
STRIPE_API_BASE = "https://api.stripe.com/v1"

if not STRIPE_API_KEY:
    raise ValueError("STRIPE_SECRET_KEY not found in environment variables.")


def fetch_all_stripe_customers():
    """Fetch every customer from Stripe using cursor-based pagination (100/page)."""
    all_customers = []
    starting_after = None
    page = 1

    while True:
        params = {"limit": 100}
        if starting_after:
            params["starting_after"] = starting_after

        try:
            resp = requests.get(
                f"{STRIPE_API_BASE}/customers",
                headers={"Authorization": f"Bearer {STRIPE_API_KEY}"},
                params=params,
                timeout=30,
            )
            resp.raise_for_status()
            data = resp.json()
            customers = data.get("data", [])
            all_customers.extend(customers)
            print(f"  Stripe page {page}: {len(customers)} customers (running total: {len(all_customers)})")

            if not data.get("has_more") or not customers:
                break
            starting_after = customers[-1]["id"]
            page += 1

        except requests.exceptions.RequestException as e:
            print(f"  Stripe fetch error on page {page}: {e}")
            break

    return all_customers


# ---------------------------------------------------------------------------
# AutoCare
# ---------------------------------------------------------------------------

AUTOCARE_BASE_URL = "https://memberships.autocarepr.com/api"
AUTOCARE_CREDENTIALS = {"email": "admin_api@autocare.com", "password": "Test1234"}


def fetch_all_autocare_records():
    """Fetch every record from AutoCare using page/per_page pagination (1000/page)."""
    login = requests.post(f"{AUTOCARE_BASE_URL}/login", json=AUTOCARE_CREDENTIALS)
    token = login.json().get("accessToken")
    if not token:
        raise ValueError("AutoCare login failed — no accessToken in response.")
    print(f"  AutoCare login: {login.status_code}")

    headers = {"Authorization": f"Bearer {token}"}
    all_records = []
    page = 1

    while True:
        batch = None
        for attempt in range(1, 4):
            try:
                resp = requests.get(
                    f"{AUTOCARE_BASE_URL}/v1/marketing/data",
                    headers=headers,
                    params={"page": page, "per_page": 1000, "includeOnlyServiceType": "true"},
                    timeout=60,
                )
                batch = resp.json().get("data", [])
                break
            except (
                requests.exceptions.ChunkedEncodingError,
                requests.exceptions.ConnectionError,
                requests.exceptions.JSONDecodeError,
                ValueError,
            ) as e:
                print(f"  AutoCare page {page} attempt {attempt} failed ({type(e).__name__}): {e}. Retrying in 3s...")
                time.sleep(3)

        if batch is None:
            print(f"  AutoCare page {page} failed after 3 attempts. Stopping.")
            break

        all_records.extend(batch)
        print(f"  AutoCare page {page}: {len(batch)} records (running total: {len(all_records)})")

        if len(batch) < 1000:
            print(f"  AutoCare page {page} is the last page ({len(batch)} < 1000).")
            break
        page += 1

    return all_records


# ---------------------------------------------------------------------------
# Cross-match
# ---------------------------------------------------------------------------

def cross_match(stripe_customers, autocare_records):
    """
    Match Stripe customers to AutoCare records using:
      Stripe  customer["id"]      == AutoCare record["billingID"]
    Returns a list of dicts with both sides of each match.
    """
    autocare_by_billing_id = {
        r["billingID"]: r
        for r in autocare_records
        if r.get("billingID")
    }

    matched = []
    for customer in stripe_customers:
        sid = customer.get("id")
        if sid and sid in autocare_by_billing_id:
            matched.append({
                "stripe_id": sid,
                "stripe": customer,
                "autocare": autocare_by_billing_id[sid],
            })

    return matched


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 60)
    print("Fetching all Stripe customers...")
    print("=" * 60)
    stripe_customers = fetch_all_stripe_customers()
    print(f"\nStripe total: {len(stripe_customers)} customers\n")

    print("=" * 60)
    print("Fetching all AutoCare records...")
    print("=" * 60)
    autocare_records = fetch_all_autocare_records()
    print(f"\nAutoCare total: {len(autocare_records)} records\n")

    print("=" * 60)
    print("Cross-matching...")
    print("=" * 60)
    matched = cross_match(stripe_customers, autocare_records)

    print(f"\nResults:")
    print(f"  Stripe customers   : {len(stripe_customers)}")
    print(f"  AutoCare records   : {len(autocare_records)}")
    print(f"  Matched (same ID)  : {len(matched)}\n")

    for m in matched:
        stripe = m["stripe"]
        autocare = m["autocare"]
        name = stripe.get("name") or f"{autocare.get('firstName', '')} {autocare.get('lastName', '')}".strip()
        email = stripe.get("email") or autocare.get("email", "")
        print(
            f"  {m['stripe_id']}  |  {name:<35}  |  {email:<40}  |  clientId: {autocare.get('clientId', '')}"
        )


if __name__ == "__main__":
    main()
