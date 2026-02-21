"""
BigQuery client for storing and managing Stripe data
"""
import json
import logging
import os
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
        # AutoCare datasets (same project)
        self.autocare_raw_dataset = 'autocare_raw'
        self.autocare_processed_dataset = 'autocare_processed'
        self.autocare_metadata_dataset = 'autocare_metadata'
        # Unified and BI datasets (updated after all syncs)
        self.unified_dataset = 'unified'
        self.bi_dataset = 'bi'

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
        Insert raw JSON data into BigQuery in batches to reduce memory usage.
        
        Args:
            entity_type: Type of entity ('customers', 'subscriptions', 'invoices')
            data: List of Stripe objects
        """
        if not data:
            logger.info(f"No data to insert for {entity_type}")
            return
        
        table_name = f"{entity_type}_raw"
        table_id = f"{self.project_id}.{self.raw_dataset}.{table_name}"
        
        # Process in batches to reduce memory usage
        batch_size = 500
        total_inserted = 0
        
        for i in range(0, len(data), batch_size):
            batch = data[i:i + batch_size]
            
            # Prepare rows for insertion
            rows_to_insert = []
            for item in batch:
                row = {
                    'id': item.get('id'),
                    'json_data': json.dumps(item),
                    'ingested_at': datetime.utcnow().isoformat(),
                    'created': datetime.fromtimestamp(item.get('created', 0)).isoformat()
                }
                rows_to_insert.append(row)
            
            # Insert batch
            errors = self.client.insert_rows_json(table_id, rows_to_insert)
            
            if errors:
                logger.error(f"Errors inserting raw data batch: {errors}")
                raise Exception(f"Failed to insert raw data: {errors}")
            
            total_inserted += len(rows_to_insert)
            logger.info(f"Inserted batch {i//batch_size + 1}: {len(rows_to_insert)} rows")
        
        logger.info(f"Total inserted {total_inserted} rows into {table_id}")
    
    def upsert_processed_data(self, entity_type: str, data: List[Dict]) -> None:
        """
        Transform and upsert data into processed tables.
        
        Args:
            entity_type: Type of entity ('customers', 'subscriptions')
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
        else:
            raise ValueError(f"Unknown entity type: {entity_type}")
    
    def _upsert_customers(self, customers: List[Dict]) -> None:
        """Upsert customer data into processed table in batches."""
        table_id = f"{self.project_id}.{self.processed_dataset}.customers"
        
        batch_size = 500
        total_upserted = 0
        
        for i in range(0, len(customers), batch_size):
            batch = customers[i:i + batch_size]
            rows_to_insert = []
            
            for customer in batch:
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
                logger.error(f"Errors upserting customers batch: {errors}")
                raise Exception(f"Failed to upsert customers: {errors}")
            
            total_upserted += len(rows_to_insert)
            logger.info(f"Upserted batch {i//batch_size + 1}: {len(rows_to_insert)} customers")
        
        logger.info(f"Total upserted {total_upserted} customers")
    
    def _upsert_subscriptions(self, subscriptions: List[Dict]) -> None:
        """Upsert subscription data into processed table in batches."""
        table_id = f"{self.project_id}.{self.processed_dataset}.subscriptions"
        
        batch_size = 500
        total_upserted = 0
        
        for i in range(0, len(subscriptions), batch_size):
            batch = subscriptions[i:i + batch_size]
            rows_to_insert = []
            
            for subscription in batch:
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
                logger.error(f"Errors upserting subscriptions batch: {errors}")
                raise Exception(f"Failed to upsert subscriptions: {errors}")
            
            total_upserted += len(rows_to_insert)
            logger.info(f"Upserted batch {i//batch_size + 1}: {len(rows_to_insert)} subscriptions")
        
        logger.info(f"Total upserted {total_upserted} subscriptions")
    
    
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

    # ---------- AutoCare API (raw + processed) ----------

    def insert_autocare_raw_tiers(self, tiers: List[Dict]) -> None:
        """Append raw tier JSON to autocare_raw.tiers_raw."""
        if not tiers:
            logger.info("No AutoCare tiers to insert")
            return
        table_id = f"{self.project_id}.{self.autocare_raw_dataset}.tiers_raw"
        rows = [
            {
                "id": t.get("id", ""),
                "json_data": json.dumps(t),
                "ingested_at": datetime.utcnow().isoformat(),
            }
            for t in tiers
        ]
        errors = self.client.insert_rows_json(table_id, rows)
        if errors:
            raise Exception(f"Failed to insert AutoCare raw tiers: {errors}")
        logger.info(f"Inserted {len(rows)} rows into {table_id}")

    def insert_autocare_raw_marketing_data(self, data: List[Dict]) -> None:
        """Append raw marketing data (mixed customer/session) to autocare_raw.marketing_data_raw."""
        if not data:
            logger.info("No AutoCare marketing data to insert")
            return
        table_id = f"{self.project_id}.{self.autocare_raw_dataset}.marketing_data_raw"
        now = datetime.utcnow().isoformat()
        rows = []
        for i, item in enumerate(data):
            rid = item.get("clientId") or item.get("sessionId") or f"row_{i}"
            record_type = "session" if item.get("sessionId") else "customer"
            rows.append({
                "id": rid,
                "record_type": record_type,
                "json_data": json.dumps(item),
                "ingested_at": now,
            })
        batch_size = 500
        for i in range(0, len(rows), batch_size):
            batch = rows[i : i + batch_size]
            errors = self.client.insert_rows_json(table_id, batch)
            if errors:
                raise Exception(f"Failed to insert AutoCare raw marketing data: {errors}")
        logger.info(f"Inserted {len(rows)} rows into {table_id}")

    def upsert_autocare_processed_tiers(self, tiers: List[Dict]) -> None:
        """Replace autocare_processed.tiers with flattened tier data."""
        if not tiers:
            logger.info("No AutoCare tiers to process")
            return
        table_id = f"{self.project_id}.{self.autocare_processed_dataset}.tiers"
        try:
            self.client.query(f"TRUNCATE TABLE `{table_id}`").result()
        except Exception as e:
            logger.warning(f"TRUNCATE tiers (may not exist): {e}")
        meta = lambda t: t.get("metadata") or {}
        rows = []
        for t in tiers:
            m = meta(t)
            rows.append({
                "product_id": t.get("id"),
                "name": t.get("name"),
                "description": t.get("description"),
                "product_key": m.get("productKey"),
                "metadata_order": m.get("order"),
                "perks": m.get("perks"),
                "refund_required": m.get("refundRequired"),
                "external_api_integration": m.get("external_api_integration"),
                "validation_rules": m.get("validation_rules"),
                "validation_description": m.get("validation_description"),
                "taxable_amount": m.get("taxable_amount"),
                "updated_at": datetime.utcnow().isoformat(),
                "ingested_at": datetime.utcnow().isoformat(),
            })
        errors = self.client.insert_rows_json(table_id, rows)
        if errors:
            raise Exception(f"Failed to upsert AutoCare processed tiers: {errors}")
        logger.info(f"Upserted {len(rows)} rows into {table_id}")

    def upsert_autocare_processed_marketing_data(self, data: List[Dict]) -> None:
        """Parse marketing data into customers, subscriptions, sessions, cars; replace processed tables."""
        customers: List[Dict] = []
        subscriptions: List[Dict] = []
        sessions: List[Dict] = []
        cars: List[Dict] = []
        seen_customers: set = set()

        for item in data:
            if item.get("sessionId"):
                loc = item.get("location") or {}
                sessions.append({
                    "session_id": item.get("sessionId"),
                    "client_id": item.get("clientId") or "",
                    "session_date": item.get("sessionDate"),
                    "session_type": item.get("sessionType"),
                    "session_description": item.get("sessionDescription"),
                    "location_id": loc.get("id"),
                    "location_name": loc.get("name"),
                    "location_is_active": loc.get("isActive"),
                    "updated_at": datetime.utcnow().isoformat(),
                    "ingested_at": datetime.utcnow().isoformat(),
                })
            if item.get("clientId") or item.get("billingID") or item.get("email"):
                key = (item.get("clientId") or "", item.get("billingID") or "")
                if key in seen_customers:
                    pass
                else:
                    seen_customers.add(key)
                    customers.append({
                        "client_id": item.get("clientId") or "",
                        "billing_id": item.get("billingID"),
                        "email": item.get("email"),
                        "first_name": item.get("firstName"),
                        "last_name": item.get("lastName"),
                        "phone_number": item.get("phoneNumber"),
                        "customer_created_date": item.get("customerCreatedDate"),
                        "updated_at": datetime.utcnow().isoformat(),
                        "ingested_at": datetime.utcnow().isoformat(),
                    })
                for sub in item.get("subscriptions") or []:
                    car_ids_str = json.dumps(sub.get("carIds") or [])
                    subscriptions.append({
                        "subscription_id": sub.get("id"),
                        "client_id": item.get("clientId") or "",
                        "billing_id": item.get("billingID"),
                        "status": sub.get("status"),
                        "product_id": sub.get("productId"),
                        "car_ids": car_ids_str,
                        "updated_at": datetime.utcnow().isoformat(),
                        "ingested_at": datetime.utcnow().isoformat(),
                    })
                for car in item.get("cars") or []:
                    if not isinstance(car, dict):
                        continue
                    car_id = car.get("id") or car.get("_id") or ""
                    if not car_id:
                        continue
                    cars.append({
                        "car_id": car_id,
                        "client_id": item.get("clientId") or "",
                        "billing_id": item.get("billingID"),
                        "json_data": json.dumps(car),
                        "make": car.get("make"),
                        "model": car.get("model"),
                        "year": car.get("year"),
                        "license_plate": car.get("licensePlate") or car.get("license_plate"),
                        "color": car.get("color"),
                        "vin": car.get("vin"),
                        "updated_at": datetime.utcnow().isoformat(),
                        "ingested_at": datetime.utcnow().isoformat(),
                    })

        proj = self.project_id
        ds = self.autocare_processed_dataset

        for table_name, rows in [
            ("marketing_customers", customers),
            ("marketing_subscriptions", subscriptions),
            ("marketing_sessions", sessions),
            ("marketing_cars", cars),
        ]:
            table_id = f"{proj}.{ds}.{table_name}"
            try:
                self.client.query(f"TRUNCATE TABLE `{table_id}`").result()
            except Exception as e:
                logger.warning(f"TRUNCATE {table_name}: {e}")
            if not rows:
                continue
            batch_size = 500
            for i in range(0, len(rows), batch_size):
                errors = self.client.insert_rows_json(table_id, rows[i : i + batch_size])
                if errors:
                    raise Exception(f"Failed to insert {table_name}: {errors}")
            logger.info(f"Upserted {len(rows)} rows into {table_id}")

    def update_autocare_sync_metadata(
        self,
        entity_type: str,
        records_synced: int,
        sync_started_at: datetime,
        sync_completed_at: datetime,
        status: str,
        error_message: Optional[str] = None,
    ) -> None:
        """Append a row to autocare_metadata.sync_history."""
        table_id = f"{self.project_id}.{self.autocare_metadata_dataset}.sync_history"
        row = {
            "entity_type": entity_type,
            "last_sync_timestamp": None,
            "last_synced_id": None,
            "records_synced": records_synced,
            "sync_started_at": sync_started_at.isoformat(),
            "sync_completed_at": sync_completed_at.isoformat(),
            "status": status,
            "error_message": error_message,
        }
        errors = self.client.insert_rows_json(table_id, [row])
        if errors:
            logger.error(f"Errors updating AutoCare sync metadata: {errors}")
        else:
            logger.info(f"Updated AutoCare sync metadata for {entity_type}")

    # ---------- Unified and BI tables (run after all Stripe + AutoCare syncs) ----------

    def refresh_unified_customers(self) -> Dict[str, Any]:
        """
        Refresh unified.customers from stripe_processed.unified_customers view.
        Run after all Stripe and AutoCare syncing is done.
        """
        unified_table = f"{self.project_id}.{self.unified_dataset}.customers"
        view_ref = f"{self.project_id}.{self.processed_dataset}.unified_customers"
        try:
            # Ensure unified dataset exists
            unified_dataset_id = f"{self.project_id}.{self.unified_dataset}"
            try:
                self.client.get_dataset(unified_dataset_id)
            except NotFound:
                self.client.create_dataset(
                    bigquery.Dataset(unified_dataset_id),
                    exists_ok=True,
                )
            # Materialize view into unified.customers (view may live in stripe_processed)
            query = f"""
            CREATE OR REPLACE TABLE `{unified_table}` AS
            SELECT * FROM `{view_ref}`
            """
            self.client.query(query).result()
            logger.info(f"Refreshed {unified_table} from {view_ref}")
            return {"status": "success", "table": unified_table}
        except Exception as e:
            logger.error(f"Failed to refresh unified customers: {e}", exc_info=True)
            return {"status": "failed", "error": str(e), "table": unified_table}

    def _load_bi_snapshot_sql(self) -> str:
        """Load BI snapshot SQL from file; substitute PROJECT_ID at runtime."""
        script_dir = os.path.dirname(os.path.abspath(__file__))
        candidates = [
            os.path.join(script_dir, "sql", "create_bi_customer_360_snapshot.sql"),
            os.path.join(script_dir, "..", "sql", "create_bi_customer_360_snapshot.sql"),
        ]
        for path in candidates:
            if os.path.isfile(path):
                with open(path, "r", encoding="utf-8") as f:
                    return f.read().replace("PROJECT_ID", self.project_id)
        raise FileNotFoundError(
            "create_bi_customer_360_snapshot.sql not found in sql/ or ../sql/"
        )

    def refresh_bi_customer_360_snapshot(self) -> Dict[str, Any]:
        """
        Refresh bi.unified_customer_360_snapshot using full CTE query (latest subs, sessions, cars, counts).
        Run after unified.customers has been refreshed.
        """
        bi_table = f"{self.project_id}.{self.bi_dataset}.unified_customer_360_snapshot"
        try:
            bi_dataset_id = f"{self.project_id}.{self.bi_dataset}"
            try:
                self.client.get_dataset(bi_dataset_id)
            except NotFound:
                self.client.create_dataset(
                    bigquery.Dataset(bi_dataset_id),
                    exists_ok=True,
                )
            query = self._load_bi_snapshot_sql()
            self.client.query(query).result()
            logger.info(f"Refreshed {bi_table} (BI customer 360 snapshot)")
            return {"status": "success", "table": bi_table}
        except Exception as e:
            logger.error(f"Failed to refresh BI snapshot: {e}", exc_info=True)
            return {"status": "failed", "error": str(e), "table": bi_table}

