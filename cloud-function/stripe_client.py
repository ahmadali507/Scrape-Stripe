"""
Stripe API client for fetching data with incremental sync support
"""
import os
import requests
import logging
from typing import List, Dict, Optional
from datetime import datetime
from google.cloud import secretmanager

logger = logging.getLogger(__name__)


class StripeClient:
    """Client for interacting with Stripe API with incremental sync support."""
    
    def __init__(self):
        """Initialize Stripe client with API key from Secret Manager."""
        self.api_key = self._get_api_key()
        self.base_url = 'https://api.stripe.com/v1'
        self.headers = {
            'Authorization': f'Bearer {self.api_key}',
            'Content-Type': 'application/x-www-form-urlencoded'
        }
        
    def _get_api_key(self) -> str:
        """
        Get Stripe API key from Google Secret Manager.
        
        Returns:
            Stripe API key string
        """
        try:
            # Try to get from environment variable first (for local testing)
            api_key = os.getenv('STRIPE_SECRET_KEY')
            if api_key:
                logger.info("Using Stripe API key from environment variable")
                return api_key
            
            # Get from Secret Manager
            project_id = os.getenv('GCP_PROJECT') or os.getenv('GOOGLE_CLOUD_PROJECT')
            if not project_id:
                raise ValueError("GCP_PROJECT or GOOGLE_CLOUD_PROJECT environment variable not set")
            
            secret_name = f"projects/{project_id}/secrets/stripe-api-key/versions/latest"
            
            client = secretmanager.SecretManagerServiceClient()
            response = client.access_secret_version(request={"name": secret_name})
            api_key = response.payload.data.decode('UTF-8')
            
            logger.info("Retrieved Stripe API key from Secret Manager")
            return api_key
            
        except Exception as e:
            logger.error(f"Error getting Stripe API key: {str(e)}")
            raise
    
    def fetch_incremental_data(
        self, 
        entity_type: str, 
        since_timestamp: Optional[int] = None
    ) -> List[Dict]:
        """
        Fetch incremental data from Stripe API.
        Fetches ALL available records without any limit.
        
        Args:
            entity_type: Type of entity ('customers', 'subscriptions', 'invoices')
            since_timestamp: Unix timestamp to fetch data created after
            
        Returns:
            List of Stripe objects
        """
        endpoint_map = {
            'customers': '/customers',
            'subscriptions': '/subscriptions'
        }
        
        if entity_type not in endpoint_map:
            raise ValueError(f"Unknown entity type: {entity_type}")
        
        endpoint = endpoint_map[entity_type]
        url = f"{self.base_url}{endpoint}"
        
        # Build query parameters
        params = {'limit': 100}  # Stripe max per page
        
        # Add incremental filter if timestamp provided
        if since_timestamp:
            params['created[gt]'] = since_timestamp
            logger.info(f"Fetching {entity_type} created after timestamp {since_timestamp}")
        else:
            logger.info(f"Fetching all {entity_type} (no timestamp filter)")
        
        all_data = []
        page = 1
        
        try:
            while True:  # Continue until no more pages
                logger.info(f"    Fetching page {page}...")
                
                response = requests.get(url, headers=self.headers, params=params, timeout=30)
                response.raise_for_status()
                
                data = response.json()
                
                if not isinstance(data, dict) or 'data' not in data:
                    logger.error(f"Unexpected response structure: {data}")
                    break
                
                page_items = data.get('data', [])
                
                if not page_items:
                    logger.info(f"    No more data on page {page}")
                    break
                
                # Add all items from this page
                all_data.extend(page_items)
                
                logger.info(f"    Retrieved {len(page_items)} items (Total: {len(all_data)})")
                
                # Check if there are more pages
                has_more = data.get('has_more', False)
                if not has_more:
                    logger.info(f"    Reached end of data (has_more=False)")
                    break
                
                # Set up pagination for next page
                if page_items:
                    params['starting_after'] = page_items[-1]['id']
                
                page += 1
            
            logger.info(f"  Total {entity_type} fetched: {len(all_data)}")
            return all_data
            
        except requests.exceptions.RequestException as e:
            logger.error(f"Error fetching {entity_type} from Stripe: {str(e)}")
            if hasattr(e, 'response') and e.response is not None:
                logger.error(f"Response: {e.response.text[:500]}")
            raise
        except Exception as e:
            logger.error(f"Unexpected error fetching {entity_type}: {str(e)}")
            raise
    
    def fetch_customer_details(self, customer_id: str) -> Optional[Dict]:
        """
        Fetch detailed customer information by ID.
        
        Args:
            customer_id: Stripe customer ID
            
        Returns:
            Customer object or None
        """
        try:
            url = f"{self.base_url}/customers/{customer_id}"
            response = requests.get(url, headers=self.headers, timeout=30)
            response.raise_for_status()
            return response.json()
        except Exception as e:
            logger.error(f"Error fetching customer {customer_id}: {str(e)}")
            return None

    def fetch_subscriptions_for_customer(self, customer_id: str) -> List[Dict]:
        """
        Fetch subscriptions for a customer with price.product expanded (to get product_id).
        """
        url = f"{self.base_url}/subscriptions"
        params = {
            'customer': customer_id,
            'status': 'all',
            'limit': 100,
            'expand[]': ['data.items.data.price.product'],
        }
        all_subs = []
        starting_after = None
        try:
            while True:
                if starting_after:
                    params['starting_after'] = starting_after
                response = requests.get(url, headers=self.headers, params=params, timeout=30)
                response.raise_for_status()
                data = response.json()
                items = data.get('data', [])
                all_subs.extend(items)
                if not data.get('has_more', False) or not items:
                    break
                starting_after = items[-1]['id']
            return all_subs
        except Exception as e:
            logger.warning(f"Error fetching subscriptions for {customer_id}: {e}")
            return []

    @staticmethod
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
