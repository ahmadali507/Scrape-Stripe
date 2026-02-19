"""
Stripe to BigQuery Cloud Function
Entry point for HTTP triggered function that syncs Stripe data to BigQuery
"""
import functions_framework
from flask import Request
import logging
from datetime import datetime
from typing import Dict, Any

from stripe_client import StripeClient
from bigquery_client import BigQueryClient
from receiver_client import build_ghl_customers, send_new_customers

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@functions_framework.http
def sync_handler(request: Request) -> tuple[str, int]:
    """
    HTTP Cloud Function entry point for Stripe to BigQuery sync.
    
    Args:
        request: Flask request object
        
    Returns:
        Tuple of (response_message, http_status_code)
    """
    try:
        logger.info("=" * 60)
        logger.info("Starting Stripe to BigQuery sync")
        logger.info(f"Triggered at: {datetime.utcnow().isoformat()}")
        logger.info("=" * 60)
        
        # Parse request parameters (optional entity filter)
        request_json = request.get_json(silent=True)
        entities = None
        
        if request_json and 'entities' in request_json:
            entities = request_json['entities']
            if isinstance(entities, str):
                entities = [entities]
            logger.info(f"Syncing specific entities: {entities}")
        else:
            entities = ['customers', 'subscriptions']
            logger.info(f"Syncing all entities: {entities}")
        
        # Initialize clients
        stripe_client = StripeClient()
        bq_client = BigQueryClient()
        
        # Sync results
        results = {}
        overall_success = True
        
        # Sync each entity type
        for entity_type in entities:
            try:
                logger.info(f"\n--- Syncing {entity_type} ---")
                result = sync_entity(stripe_client, bq_client, entity_type)
                results[entity_type] = result
                
                if result['status'] != 'success':
                    overall_success = False
                    
            except Exception as e:
                logger.error(f"Error syncing {entity_type}: {str(e)}", exc_info=True)
                results[entity_type] = {
                    'status': 'failed',
                    'error': str(e),
                    'records_synced': 0
                }
                overall_success = False
        
        # Build response
        logger.info("\n" + "=" * 60)
        logger.info("Sync Complete")
        logger.info("=" * 60)
        
        response = {
            'success': overall_success,
            'timestamp': datetime.utcnow().isoformat(),
            'results': results
        }
        
        status_code = 200 if overall_success else 500
        
        logger.info(f"Overall status: {'SUCCESS' if overall_success else 'FAILED'}")
        for entity, result in results.items():
            logger.info(f"  {entity}: {result.get('records_synced', 0)} records - {result.get('status')}")
        
        return (str(response), status_code)
        
    except Exception as e:
        logger.error(f"Fatal error in sync handler: {str(e)}", exc_info=True)
        return (f"Error: {str(e)}", 500)


def sync_entity(stripe_client: StripeClient, bq_client: BigQueryClient, entity_type: str) -> Dict[str, Any]:
    """
    Sync a specific entity type from Stripe to BigQuery.
    
    Args:
        stripe_client: Initialized Stripe client
        bq_client: Initialized BigQuery client
        entity_type: Type of entity ('customers', 'subscriptions', 'invoices')
        
    Returns:
        Dictionary with sync results
    """
    sync_started_at = datetime.utcnow()
    
    try:
        # Step 1: Get last sync timestamp from BigQuery
        logger.info(f"  Getting last sync timestamp for {entity_type}...")
        last_sync_info = bq_client.get_last_sync_timestamp(entity_type)
        last_sync_timestamp = last_sync_info.get('last_sync_timestamp')
        
        logger.info(f"  Last sync: {last_sync_timestamp}")
        
        # Step 2: Fetch incremental data from Stripe
        logger.info(f"  Fetching incremental data from Stripe...")
        stripe_data = stripe_client.fetch_incremental_data(
            entity_type=entity_type,
            since_timestamp=last_sync_timestamp
        )
        
        record_count = len(stripe_data)
        logger.info(f"  Fetched {record_count} records from Stripe")
        
        if record_count == 0:
            logger.info(f"  No new records to sync for {entity_type}")
            
            # Update metadata with successful sync (no new records)
            bq_client.update_sync_metadata(
                entity_type=entity_type,
                records_synced=0,
                sync_started_at=sync_started_at,
                sync_completed_at=datetime.utcnow(),
                status='success',
                last_sync_timestamp=last_sync_timestamp
            )
            
            return {
                'status': 'success',
                'records_synced': 0,
                'message': 'No new records'
            }
        
        # Step 3: Store raw JSON in BigQuery
        logger.info(f"  Storing raw JSON data in BigQuery...")
        bq_client.insert_raw_data(entity_type, stripe_data)
        logger.info(f"  ✓ Raw data stored")
        
        # Step 4: Transform and load to processed tables
        logger.info(f"  Transforming and loading to processed table...")
        bq_client.upsert_processed_data(entity_type, stripe_data)
        logger.info(f"  ✓ Processed data loaded")
        
        # Step 5: Calculate new last_sync_timestamp
        # Use the maximum 'created' timestamp from the fetched data
        new_last_sync_timestamp = max(
            item.get('created', 0) for item in stripe_data
        )
        
        # Step 6: Update metadata
        sync_completed_at = datetime.utcnow()
        logger.info(f"  Updating sync metadata...")
        bq_client.update_sync_metadata(
            entity_type=entity_type,
            records_synced=record_count,
            sync_started_at=sync_started_at,
            sync_completed_at=sync_completed_at,
            status='success',
            last_sync_timestamp=new_last_sync_timestamp
        )
        logger.info(f"  ✓ Metadata updated")

        # Send new customers to GoHighLevel (Replit) — mandatory when we have new customers
        if entity_type == 'customers' and record_count > 0:
            try:
                ghl_customers = build_ghl_customers(stripe_client, stripe_data)
                if ghl_customers:
                    if not send_new_customers(ghl_customers):
                        logger.error("  GoHighLevel webhook not configured or send failed (mandatory)")
                        bq_client.update_sync_metadata(
                            entity_type=entity_type,
                            records_synced=record_count,
                            sync_started_at=sync_started_at,
                            sync_completed_at=datetime.utcnow(),
                            status='failed',
                            last_sync_timestamp=new_last_sync_timestamp,
                            error_message='GoHighLevel webhook not configured or send failed'
                        )
                        return {
                            'status': 'failed',
                            'error': 'GoHighLevel webhook not configured or send failed',
                            'records_synced': record_count,
                            'last_sync_timestamp': new_last_sync_timestamp
                        }
                    logger.info(f"  ✓ New customers sent to GHL webhook ({len(ghl_customers)} entries)")
                else:
                    logger.info(f"  No GHL-valid customers to send (missing email/phone/name)")
            except Exception as send_err:
                logger.error(f"  GHL webhook send failed (mandatory): {send_err}", exc_info=True)
                bq_client.update_sync_metadata(
                    entity_type=entity_type,
                    records_synced=record_count,
                    sync_started_at=sync_started_at,
                    sync_completed_at=datetime.utcnow(),
                    status='failed',
                    error_message=f'GHL webhook send failed: {send_err}'
                )
                return {
                    'status': 'failed',
                    'error': str(send_err),
                    'records_synced': record_count,
                    'last_sync_timestamp': new_last_sync_timestamp
                }

        return {
            'status': 'success',
            'records_synced': record_count,
            'last_sync_timestamp': new_last_sync_timestamp
        }
        
    except Exception as e:
        logger.error(f"  Error syncing {entity_type}: {str(e)}", exc_info=True)
        
        # Update metadata with failure
        try:
            bq_client.update_sync_metadata(
                entity_type=entity_type,
                records_synced=0,
                sync_started_at=sync_started_at,
                sync_completed_at=datetime.utcnow(),
                status='failed',
                error_message=str(e)
            )
        except Exception as meta_error:
            logger.error(f"  Could not update metadata: {str(meta_error)}")
        
        return {
            'status': 'failed',
            'error': str(e),
            'records_synced': 0
        }

