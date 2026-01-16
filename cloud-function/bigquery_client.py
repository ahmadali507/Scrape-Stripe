"""
BigQuery client for storing and managing Stripe data
"""
import json
import logging
from typing import List, Dict, Optional, Any
from datetime import datetime
from google.cloud import bigquery
from google.cloud.exceptions import NotFound

logger = logging.getLogger(__name__)


class BigQueryClient:
    """Client for BigQuery operations in the Stripe data pipeline."""
    
    def __init__(self, project_id: Optional[str] = None):
        """
        Initialize BigQuery client.
        
        Args:
            project_id: GCP project ID (optional, will use default if not provided)
        """
        self.client = bigquery.Client(project=project_id)
        self.project_id = project_id or self.client.project
        
        # Dataset names
        self.raw_dataset = 'stripe_raw'
        self.processed_dataset = 'stripe_processed'
        self.metadata_dataset = 'stripe_metadata'
        
        logger.info(f"Initialized BigQuery client for project: {self.project_id}")
    
    def get_last_sync_timestamp(self, entity_type: str) -> Dict[str, Any]:
        """
        Get the last sync timestamp for an entity type.
        
        Args:
            entity_type: Type of entity ('customers', 'subscriptions', 'invoices')
            
        Returns:
            Dictionary with last sync information
        """
        query = f"""
        SELECT 
            entity_type,
            last_sync_timestamp,
            UNIX_SECONDS(last_sync_timestamp) as last_sync_unix,
            last_synced_id,
            records_synced,
            sync_completed_at,
            status
        FROM `{self.project_id}.{self.metadata_dataset}.sync_history`
        WHERE entity_type = @entity_type
        ORDER BY sync_completed_at DESC
        LIMIT 1
        """
        
        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("entity_type", "STRING", entity_type)
            ]
        )
        
        try:
            query_job = self.client.query(query, job_config=job_config)
            results = list(query_job.result())
            
            if results:
                row = results[0]
                return {
                    'entity_type': row.entity_type,
                    'last_sync_timestamp': row.last_sync_unix,
                    'last_synced_id': row.last_synced_id,
                    'records_synced': row.records_synced,
                    'status': row.status
                }
            else:
                # No previous sync, return epoch timestamp
                logger.info(f"No previous sync found for {entity_type}, starting from epoch")
                return {
                    'entity_type': entity_type,
                    'last_sync_timestamp': 0,
                    'last_synced_id': None,
                    'records_synced': 0,
                    'status': 'pending'
                }
                
        except Exception as e:
            logger.error(f"Error getting last sync timestamp: {str(e)}")
            # Return epoch on error to be safe
            return {
                'entity_type': entity_type,
                'last_sync_timestamp': 0,
                'last_synced_id': None,
                'records_synced': 0,
                'status': 'error'
            }
    
    def insert_raw_data(self, entity_type: str, data: List[Dict]) -> None:
        """
        Insert raw JSON data into BigQuery.
        
        Args:
            entity_type: Type of entity ('customers', 'subscriptions', 'invoices')
            data: List of Stripe objects
        """
        if not data:
            logger.info(f"No data to insert for {entity_type}")
            return
        
        table_name = f"{entity_type}_raw"
        table_id = f"{self.project_id}.{self.raw_dataset}.{table_name}"
        
        # Prepare rows for insertion
        rows_to_insert = []
        for item in data:
            row = {
                'id': item.get('id'),
                'json_data': json.dumps(item),
                'ingested_at': datetime.utcnow().isoformat(),
                'created': datetime.fromtimestamp(item.get('created', 0)).isoformat()
            }
            rows_to_insert.append(row)
        
        # Insert data
        errors = self.client.insert_rows_json(table_id, rows_to_insert)
        
        if errors:
            logger.error(f"Errors inserting raw data: {errors}")
            raise Exception(f"Failed to insert raw data: {errors}")
        
        logger.info(f"Inserted {len(rows_to_insert)} rows into {table_id}")
    
    def upsert_processed_data(self, entity_type: str, data: List[Dict]) -> None:
        """
        Transform and upsert data into processed tables.
        
        Args:
            entity_type: Type of entity ('customers', 'subscriptions', 'invoices')
            data: List of Stripe objects
        """
        if not data:
            logger.info(f"No data to process for {entity_type}")
            return
        
        # Transform based on entity type
        if entity_type == 'customers':
            self._upsert_customers(data)
        elif entity_type == 'subscriptions':
            self._upsert_subscriptions(data)
        elif entity_type == 'invoices':
            self._upsert_invoices(data)
        else:
            raise ValueError(f"Unknown entity type: {entity_type}")
    
    def _upsert_customers(self, customers: List[Dict]) -> None:
        """Upsert customer data into processed table."""
        table_id = f"{self.project_id}.{self.processed_dataset}.customers"
        
        rows_to_insert = []
        for customer in customers:
            address = customer.get('address', {}) or {}
            
            row = {
                'customer_id': customer.get('id'),
                'object_type': customer.get('object'),
                'email': customer.get('email'),
                'name': customer.get('name'),
                'description': customer.get('description'),
                'phone': customer.get('phone'),
                'created': datetime.fromtimestamp(customer.get('created', 0)).isoformat(),
                'created_timestamp': customer.get('created', 0),
                
                # Address
                'address_line1': address.get('line1'),
                'address_line2': address.get('line2'),
                'address_city': address.get('city'),
                'address_state': address.get('state'),
                'address_postal_code': address.get('postal_code'),
                'address_country': address.get('country'),
                
                # Billing
                'currency': customer.get('currency'),
                'balance': customer.get('balance'),
                'delinquent': customer.get('delinquent'),
                
                # Metadata
                'default_source': customer.get('default_source'),
                'invoice_prefix': customer.get('invoice_prefix'),
                
                # Tracking
                'updated_at': datetime.utcnow().isoformat(),
                'ingested_at': datetime.utcnow().isoformat()
            }
            rows_to_insert.append(row)
        
        errors = self.client.insert_rows_json(table_id, rows_to_insert)
        
        if errors:
            logger.error(f"Errors upserting customers: {errors}")
            raise Exception(f"Failed to upsert customers: {errors}")
        
        logger.info(f"Upserted {len(rows_to_insert)} customers")
    
    def _upsert_subscriptions(self, subscriptions: List[Dict]) -> None:
        """Upsert subscription data into processed table."""
        table_id = f"{self.project_id}.{self.processed_dataset}.subscriptions"
        
        rows_to_insert = []
        for subscription in subscriptions:
            # Extract plan/price information
            items = subscription.get('items', {}).get('data', [])
            price_info = {}
            if items:
                price = items[0].get('price', {})
                price_info = {
                    'amount': price.get('unit_amount', 0) / 100 if price.get('unit_amount') else None,
                    'currency': price.get('currency'),
                    'interval': price.get('recurring', {}).get('interval'),
                    'interval_count': price.get('recurring', {}).get('interval_count'),
                    'plan_name': price.get('nickname') or price.get('product'),
                    'plan_id': price.get('id'),
                    'product_id': price.get('product')
                }
            
            row = {
                'subscription_id': subscription.get('id'),
                'object_type': subscription.get('object'),
                'status': subscription.get('status'),
                'created': datetime.fromtimestamp(subscription.get('created', 0)).isoformat(),
                'created_timestamp': subscription.get('created', 0),
                
                # Period
                'current_period_start': datetime.fromtimestamp(subscription.get('current_period_start', 0)).isoformat() if subscription.get('current_period_start') else None,
                'current_period_end': datetime.fromtimestamp(subscription.get('current_period_end', 0)).isoformat() if subscription.get('current_period_end') else None,
                'cancel_at_period_end': subscription.get('cancel_at_period_end'),
                'canceled_at': datetime.fromtimestamp(subscription.get('canceled_at', 0)).isoformat() if subscription.get('canceled_at') else None,
                'ended_at': datetime.fromtimestamp(subscription.get('ended_at', 0)).isoformat() if subscription.get('ended_at') else None,
                
                # Customer
                'customer_id': subscription.get('customer'),
                
                # Pricing
                'currency': price_info.get('currency') or subscription.get('currency'),
                'amount': price_info.get('amount'),
                'subscription_interval': price_info.get('interval'),
                'interval_count': price_info.get('interval_count'),
                
                # Plan
                'plan_name': price_info.get('plan_name'),
                'plan_id': price_info.get('plan_id'),
                'product_id': price_info.get('product_id'),
                
                # Collection
                'collection_method': subscription.get('collection_method'),
                
                # Tracking
                'updated_at': datetime.utcnow().isoformat(),
                'ingested_at': datetime.utcnow().isoformat()
            }
            rows_to_insert.append(row)
        
        errors = self.client.insert_rows_json(table_id, rows_to_insert)
        
        if errors:
            logger.error(f"Errors upserting subscriptions: {errors}")
            raise Exception(f"Failed to upsert subscriptions: {errors}")
        
        logger.info(f"Upserted {len(rows_to_insert)} subscriptions")
    
    def _upsert_invoices(self, invoices: List[Dict]) -> None:
        """Upsert invoice data into processed table."""
        table_id = f"{self.project_id}.{self.processed_dataset}.invoices"
        
        rows_to_insert = []
        for invoice in invoices:
            row = {
                'invoice_id': invoice.get('id'),
                'object_type': invoice.get('object'),
                'number': invoice.get('number'),
                'status': invoice.get('status'),
                'created': datetime.fromtimestamp(invoice.get('created', 0)).isoformat(),
                'created_timestamp': invoice.get('created', 0),
                
                # Customer
                'customer_id': invoice.get('customer'),
                'customer_email': invoice.get('customer_email'),
                'customer_name': invoice.get('customer_name'),
                
                # Subscription
                'subscription_id': invoice.get('subscription'),
                
                # Amounts
                'currency': invoice.get('currency'),
                'amount_due': invoice.get('amount_due'),
                'amount_paid': invoice.get('amount_paid'),
                'amount_remaining': invoice.get('amount_remaining'),
                'subtotal': invoice.get('subtotal'),
                'total': invoice.get('total'),
                'tax': invoice.get('tax'),
                
                # Dates
                'due_date': datetime.fromtimestamp(invoice.get('due_date', 0)).isoformat() if invoice.get('due_date') else None,
                'paid_at': datetime.fromtimestamp(invoice.get('status_transitions', {}).get('paid_at', 0)).isoformat() if invoice.get('status_transitions', {}).get('paid_at') else None,
                'period_start': datetime.fromtimestamp(invoice.get('period_start', 0)).isoformat() if invoice.get('period_start') else None,
                'period_end': datetime.fromtimestamp(invoice.get('period_end', 0)).isoformat() if invoice.get('period_end') else None,
                
                # Payment
                'paid': invoice.get('paid'),
                'attempted': invoice.get('attempted'),
                'attempt_count': invoice.get('attempt_count'),
                
                # Details
                'description': invoice.get('description'),
                'statement_descriptor': invoice.get('statement_descriptor'),
                
                # Tracking
                'updated_at': datetime.utcnow().isoformat(),
                'ingested_at': datetime.utcnow().isoformat()
            }
            rows_to_insert.append(row)
        
        errors = self.client.insert_rows_json(table_id, rows_to_insert)
        
        if errors:
            logger.error(f"Errors upserting invoices: {errors}")
            raise Exception(f"Failed to upsert invoices: {errors}")
        
        logger.info(f"Upserted {len(rows_to_insert)} invoices")
    
    def update_sync_metadata(
        self,
        entity_type: str,
        records_synced: int,
        sync_started_at: datetime,
        sync_completed_at: datetime,
        status: str,
        last_sync_timestamp: Optional[int] = None,
        error_message: Optional[str] = None
    ) -> None:
        """
        Update sync metadata table.
        
        Args:
            entity_type: Type of entity
            records_synced: Number of records synced
            sync_started_at: When sync started
            sync_completed_at: When sync completed
            status: Sync status ('success', 'failed', 'in_progress')
            last_sync_timestamp: Unix timestamp of last synced record
            error_message: Error message if failed
        """
        table_id = f"{self.project_id}.{self.metadata_dataset}.sync_history"
        
        row = {
            'entity_type': entity_type,
            'last_sync_timestamp': datetime.fromtimestamp(last_sync_timestamp).isoformat() if last_sync_timestamp else None,
            'last_synced_id': None,  # Could be enhanced to track last ID
            'records_synced': records_synced,
            'sync_started_at': sync_started_at.isoformat(),
            'sync_completed_at': sync_completed_at.isoformat(),
            'status': status,
            'error_message': error_message
        }
        
        errors = self.client.insert_rows_json(table_id, [row])
        
        if errors:
            logger.error(f"Errors updating sync metadata: {errors}")
            raise Exception(f"Failed to update sync metadata: {errors}")
        
        logger.info(f"Updated sync metadata for {entity_type}")

