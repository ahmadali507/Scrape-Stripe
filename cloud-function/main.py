"""
Stripe to BigQuery Cloud Function
Entry point for HTTP triggered function that syncs Stripe + AutoCare data to BigQuery.

Default behaviour (no body / entities not specified):
  - AutoCare sync (tiers + marketing data) — skipped when skip_autocare=true
  - Stripe incremental sync (customers, subscriptions)
  - unified.customers refresh
  - bi.unified_customer_360_snapshot refresh

When called by the AutoCare Cloud Run Job after it finishes, it passes
{"skip_autocare": true} so the function only handles Stripe + unified/BI.
"""
import json
import os
import functions_framework
from flask import Request
import logging
from datetime import datetime
from typing import Dict, List, Tuple, Any

from stripe_client import StripeClient
from bigquery_client import BigQueryClient
from receiver_client import build_ghl_customers, send_new_customers

try:
    from autocare_client import AutoCareClient
except ImportError:
    AutoCareClient = None

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
        
        # Parse request parameters
        request_json = request.get_json(silent=True) or {}
        entities = request_json.get('entities')
        skip_autocare = request_json.get('skip_autocare', False)

        if entities is not None:
            if isinstance(entities, str):
                entities = [entities]
            logger.info(f"Syncing specific Stripe entities: {entities}")
        else:
            entities = ['customers', 'subscriptions']
            logger.info(f"Syncing Stripe entities: {entities}")

        if skip_autocare:
            logger.info("skip_autocare=true — AutoCare sync handled by Cloud Run Job, skipping here")

        # Initialize clients
        stripe_client = StripeClient()
        bq_client = BigQueryClient()

        # Sync results
        results = {}
        overall_success = True

        # Sync AutoCare unless explicitly skipped (Cloud Run Job handles it separately)
        if not skip_autocare:
            try:
                logger.info("\n--- Syncing AutoCare (tiers + marketing data) ---")
                ac_result = sync_autocare_to_bigquery(bq_client)
                results['autocare'] = ac_result
                if ac_result.get('status') not in ('success', 'partial'):
                    overall_success = False
            except Exception as e:
                logger.error(f"AutoCare sync failed: {e}", exc_info=True)
                results['autocare'] = {'status': 'failed', 'error': str(e), 'records_synced': 0}
                overall_success = False
        else:
            results['autocare'] = {'status': 'skipped', 'message': 'handled by Cloud Run Job'}

        # Sync each Stripe entity type
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

        # Update unified tables after all Stripe and AutoCare syncing is done
        try:
            logger.info("\n--- Updating unified tables (unified.customers + BI snapshot) ---")
            unified_result = bq_client.refresh_unified_customers()
            results['unified_customers'] = unified_result
            if unified_result.get('status') != 'success':
                overall_success = False
            # BI snapshot reads from unified.customers — only run if unified refresh succeeded
            if unified_result.get('status') == 'success':
                bi_result = bq_client.refresh_bi_customer_360_snapshot()
                results['bi_snapshot'] = bi_result
                if bi_result.get('status') != 'success':
                    overall_success = False
                logger.info("  ✓ Unified tables updated")
            else:
                results['bi_snapshot'] = {
                    'status': 'skipped',
                    'error': 'unified.customers not created; run sql/create_unified_customer_view.sql and ensure view exists'
                }
                logger.warning("  BI snapshot skipped (unified.customers missing or view not created)")
        except Exception as e:
            logger.error(f"Error updating unified tables: {e}", exc_info=True)
            results['unified_customers'] = {'status': 'failed', 'error': str(e)}
            results['bi_snapshot'] = {'status': 'failed', 'error': str(e)}
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


def _get_autocare_credentials() -> tuple:
    """Get (email, password) from env or Secret Manager. Returns (None, None) if not configured."""
    email = os.getenv("AUTOCARE_API_EMAIL")
    password = os.getenv("AUTOCARE_API_PASSWORD")
    if email and password:
        return email.strip(), password.strip()
    project_id = os.getenv("GCP_PROJECT") or os.getenv("GOOGLE_CLOUD_PROJECT")
    if not project_id:
        return None, None
    try:
        from google.cloud import secretmanager
        client = secretmanager.SecretManagerServiceClient()
        if not email:
            name = f"projects/{project_id}/secrets/autocare-api-email/versions/latest"
            response = client.access_secret_version(request={"name": name})
            email = response.payload.data.decode("UTF-8").strip()
        if not password:
            name = f"projects/{project_id}/secrets/autocare-api-password/versions/latest"
            response = client.access_secret_version(request={"name": name})
            password = response.payload.data.decode("UTF-8").strip()
        if email and password:
            logger.info("Retrieved AutoCare credentials from Secret Manager")
        return email or None, password or None
    except Exception as e:
        logger.debug("Could not get AutoCare credentials from Secret Manager: %s", e)
        return email or None, password or None


def parse_marketing_page(
    data: List[Dict],
) -> Tuple[List[Dict], List[Dict], List[Dict], List[Dict]]:
    """
    Parse one page of AutoCare marketing API records into four entity lists:
    (customers, subscriptions, sessions, cars).

    Deduplicates customers within the page by (client_id, billing_id).
    Cross-page duplicates are handled by the BigQuery MERGE at job end.
    """
    customers:     List[Dict] = []
    subscriptions: List[Dict] = []
    sessions:      List[Dict] = []
    cars:          List[Dict] = []
    seen_customers: set = set()
    now = datetime.utcnow().isoformat()

    for item in data:
        # Sessions
        if item.get("sessionId"):
            loc = item.get("location") or {}
            sessions.append({
                "session_id":          item.get("sessionId"),
                "client_id":           item.get("clientId") or "",
                "session_date":        item.get("sessionDate"),
                "session_type":        item.get("sessionType"),
                "session_description": item.get("sessionDescription"),
                "location_id":         loc.get("id"),
                "location_name":       loc.get("name"),
                "location_is_active":  loc.get("isActive"),
                "updated_at":          now,
                "ingested_at":         now,
            })

        # Customers + subscriptions + cars
        if item.get("clientId") or item.get("billingID") or item.get("email"):
            key = (item.get("clientId") or "", item.get("billingID") or "")
            if key not in seen_customers:
                seen_customers.add(key)
                customers.append({
                    "client_id":             item.get("clientId") or "",
                    "billing_id":            item.get("billingID"),
                    "email":                 item.get("email"),
                    "first_name":            item.get("firstName"),
                    "last_name":             item.get("lastName"),
                    "phone_number":          item.get("phoneNumber"),
                    "customer_created_date": item.get("customerCreatedDate"),
                    "updated_at":            now,
                    "ingested_at":           now,
                })

            for sub in item.get("subscriptions") or []:
                subscriptions.append({
                    "subscription_id": sub.get("id"),
                    "client_id":       item.get("clientId") or "",
                    "billing_id":      item.get("billingID"),
                    "status":          sub.get("status"),
                    "product_id":      sub.get("productId"),
                    "car_ids":         json.dumps(sub.get("carIds") or []),
                    "updated_at":      now,
                    "ingested_at":     now,
                })

            for car in item.get("cars") or []:
                if not isinstance(car, dict):
                    continue
                car_id = car.get("id") or car.get("_id") or ""
                if not car_id:
                    continue
                cars.append({
                    "car_id":        car_id,
                    "client_id":     item.get("clientId") or "",
                    "billing_id":    item.get("billingID"),
                    "json_data":     json.dumps(car),
                    "make":          car.get("make"),
                    "model":         car.get("model"),
                    "year":          car.get("year"),
                    "license_plate": car.get("licensePlate") or car.get("license_plate"),
                    "color":         car.get("color"),
                    "vin":           car.get("vin"),
                    "updated_at":    now,
                    "ingested_at":   now,
                })

    return customers, subscriptions, sessions, cars


def sync_autocare_to_bigquery(bq_client: BigQueryClient) -> Dict[str, Any]:
    """
    Stream AutoCare tiers + marketing data page-by-page into BigQuery.

    Architecture:
      1. Tiers   → TRUNCATE + full reload (small reference table, fast)
      2. Marketing data (700k+ records):
         a. prepare_autocare_staging() — TRUNCATE staging tables once
         b. For each page (~1 000 records):
              - Append raw records to autocare_raw.marketing_data_raw
              - Parse into 4 entity types
              - INSERT parsed rows into staging tables
         c. merge_autocare_staging_to_processed() — one MERGE per entity
            at the end (dedup + upsert into processed tables)

    Memory: bounded to O(1 page) ≈ 2–3 MB regardless of dataset size.
    """
    if AutoCareClient is None:
        return {"status": "failed", "error": "autocare_client not available", "records_synced": 0}

    email, password = _get_autocare_credentials()
    if not email or not password:
        return {
            "status": "failed",
            "error": (
                "AUTOCARE_API_EMAIL and AUTOCARE_API_PASSWORD not set "
                "(set env vars or store in Secret Manager: "
                "autocare-api-email, autocare-api-password)"
            ),
            "records_synced": 0,
        }

    sync_started_at = datetime.utcnow()

    try:
        ac = AutoCareClient(email=email, password=password)

        # ── 1. Tiers (small, full reload) ────────────────────────────
        tiers = ac.get_tiers()
        bq_client.insert_autocare_raw_tiers(tiers)
        bq_client.upsert_autocare_processed_tiers(tiers)
        bq_client.update_autocare_sync_metadata(
            "autocare_tiers", len(tiers), sync_started_at, datetime.utcnow(), "success"
        )
        logger.info(f"Tiers synced: {len(tiers)} records")

        # ── 2. Marketing data (streaming) ────────────────────────────
        bq_client.prepare_autocare_staging()

        total_records = 0
        total_pages   = 0
        failed_pages:  List[int] = []

        for page_num, page_data in enumerate(ac.stream_marketing_data_pages(), start=1):
            try:
                # Raw audit log — append all records from this page
                bq_client.insert_autocare_raw_marketing_page(page_data)

                # Parse page into entity types and write to staging
                customers, subscriptions, sessions, cars = parse_marketing_page(page_data)
                bq_client.insert_autocare_staging_batch(customers, subscriptions, sessions, cars)

                total_records += len(page_data)
                total_pages    = page_num

                if page_num % 50 == 0:
                    logger.info(
                        "Progress: page %d — %d records so far", page_num, total_records
                    )

            except Exception as page_err:
                logger.error("Page %d failed (skipping): %s", page_num, page_err, exc_info=True)
                failed_pages.append(page_num)
                continue

        logger.info(
            "Streaming complete: %d pages, %d records, %d failed pages",
            total_pages, total_records, len(failed_pages),
        )

        # ── 3. MERGE staging → processed (one pass per entity) ───────
        bq_client.merge_autocare_staging_to_processed()

        status = "success" if not failed_pages else "partial"
        bq_client.update_autocare_sync_metadata(
            "autocare_marketing_data",
            total_records,
            sync_started_at,
            datetime.utcnow(),
            status,
            error_message=f"Failed pages: {failed_pages}" if failed_pages else None,
        )

        return {
            "status":        status,
            "records_synced": total_records,
            "tiers":          len(tiers),
            "pages":          total_pages,
            "failed_pages":   failed_pages,
        }

    except Exception as e:
        logger.exception("AutoCare sync failed")
        bq_client.update_autocare_sync_metadata(
            "autocare_marketing_data", 0, sync_started_at, datetime.utcnow(), "failed",
            error_message=str(e),
        )
        return {"status": "failed", "error": str(e), "records_synced": 0}


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

