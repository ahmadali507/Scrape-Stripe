"""
Client to POST new Stripe customers to GoHighLevel (Replit) webhook.
Transforms Stripe customers into GHL format (customer_id, email, name, phone, product_id)
and sends to POST /api/webhooks/new-customers.
URL and secret are read from env vars or GCP Secret Manager (replit-webhook-url, replit-webhook-secret).
"""
import os
import logging
import requests
from typing import List, Dict, Any, Optional, Tuple
from datetime import datetime

logger = logging.getLogger(__name__)

REPLIT_WEBHOOK_URL_ENV = "REPLIT_WEBHOOK_URL"
REPLIT_WEBHOOK_SECRET_ENV = "REPLIT_WEBHOOK_SECRET"
HEADER_SECRET = "x-webhook-secret"
MAX_CUSTOMERS_PER_REQUEST = 10_000

# Secret Manager secret names (used when env vars are not set)
SECRET_NAME_WEBHOOK_URL = "replit-webhook-url"
SECRET_NAME_WEBHOOK_SECRET = "replit-webhook-secret"


def _get_webhook_config() -> Tuple[Optional[str], Optional[str]]:
    """Get (url, secret) from env or Secret Manager. Returns (None, None) if not configured."""
    url = os.getenv(REPLIT_WEBHOOK_URL_ENV)
    secret = os.getenv(REPLIT_WEBHOOK_SECRET_ENV)
    if url and secret:
        return url.strip(), secret.strip()

    project_id = os.getenv("GCP_PROJECT") or os.getenv("GOOGLE_CLOUD_PROJECT")
    if not project_id:
        return None, None

    try:
        from google.cloud import secretmanager
        client = secretmanager.SecretManagerServiceClient()
        if not url:
            name = f"projects/{project_id}/secrets/{SECRET_NAME_WEBHOOK_URL}/versions/latest"
            response = client.access_secret_version(request={"name": name})
            url = response.payload.data.decode("UTF-8").strip()
        if not secret:
            name = f"projects/{project_id}/secrets/{SECRET_NAME_WEBHOOK_SECRET}/versions/latest"
            response = client.access_secret_version(request={"name": name})
            secret = response.payload.data.decode("UTF-8").strip()
        if url and secret:
            logger.info("Retrieved Replit webhook config from Secret Manager")
        return url or None, secret or None
    except Exception as e:
        logger.debug(f"Could not get Replit webhook from Secret Manager: {e}")
        return url or None, secret or None


def _ghl_customer_from_stripe(
    customer: Dict[str, Any],
    product_id: Optional[str],
) -> Dict[str, Any]:
    """Build one GHL-format customer object. At least one of email, phone, name required."""
    out = {
        "customer_id": customer.get("id"),
        "email": customer.get("email") or None,
        "name": customer.get("name") or None,
        "phone": customer.get("phone") or None,
    }
    if product_id is not None:
        out["product_id"] = product_id
    return {k: v for k, v in out.items() if v is not None}


def build_ghl_customers(
    stripe_client: Any,
    stripe_customers: List[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    """
    Transform Stripe customers into GoHighLevel webhook format.
    Fetches subscriptions per customer to get product_id(s).
    One GHL entry per (customer, product_id); if no subscriptions, one entry with no product_id.

    Args:
        stripe_client: StripeClient instance (must have fetch_subscriptions_for_customer, get_product_ids_from_subscription)
        stripe_customers: List of Stripe customer objects

    Returns:
        List of GHL-format customer objects: { customer_id, email?, name?, phone?, product_id? }
    """
    ghl_list = []
    for customer in stripe_customers:
        cid = customer.get("id")
        if not cid:
            continue
        subs = stripe_client.fetch_subscriptions_for_customer(cid)
        product_ids = []
        for sub in subs:
            product_ids.extend(stripe_client.get_product_ids_from_subscription(sub))
        product_ids = list(dict.fromkeys(product_ids))

        if product_ids:
            for pid in product_ids:
                entry = _ghl_customer_from_stripe(customer, pid)
                if entry.get("email") or entry.get("phone") or entry.get("name"):
                    ghl_list.append(entry)
        else:
            entry = _ghl_customer_from_stripe(customer, None)
            if entry.get("email") or entry.get("phone") or entry.get("name"):
                ghl_list.append(entry)

    return ghl_list


def send_new_customers(
    ghl_customers: List[Dict[str, Any]],
    tags: Optional[List[str]] = None,
) -> bool:
    """
    POST customers to GoHighLevel webhook (Replit).
    Payload: { "customers": [...], "tags": [] }
    Auth: x-webhook-secret or Authorization: Bearer (same value).

    Args:
        ghl_customers: List of GHL-format objects (customer_id, email?, name?, phone?, product_id?).
        tags: Optional extra tags applied to all contacts.

    Returns:
        True if sent successfully, False if not configured or send failed.
    """
    url, secret = _get_webhook_config()

    if not url or not secret:
        logger.error(
            "GoHighLevel webhook required but not configured "
            "(set REPLIT_WEBHOOK_URL and REPLIT_WEBHOOK_SECRET, or store in Secret Manager: replit-webhook-url, replit-webhook-secret)"
        )
        return False

    payload = {
        "customers": ghl_customers,
        "tags": tags if tags is not None else [],
    }
    headers = {
        "Content-Type": "application/json",
        HEADER_SECRET: secret,
        "Authorization": f"Bearer {secret}",
    }

    # GHL endpoint accepts max 10,000 per request; chunk if needed
    total_sent = 0
    for i in range(0, len(ghl_customers), MAX_CUSTOMERS_PER_REQUEST):
        chunk = ghl_customers[i : i + MAX_CUSTOMERS_PER_REQUEST]
        chunk_payload = {"customers": chunk, "tags": payload["tags"]}
        try:
            response = requests.post(
                url, json=chunk_payload, headers=headers, timeout=120
            )
            response.raise_for_status()
            total_sent += len(chunk)
            logger.info(f"Sent {len(chunk)} customers to GHL webhook (total so far: {total_sent})")
        except requests.exceptions.RequestException as e:
            logger.warning(f"Failed to send customers to GHL webhook: {e}")
            return False

    logger.info(f"Sent {total_sent} new customers to receiver: {url}")
    return True
