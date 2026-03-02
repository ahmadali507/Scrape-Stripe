"""
AutoCare Cloud Run Job entrypoint.

Runs the full AutoCare streaming sync (tiers + 700k+ marketing records),
then triggers the Stripe Cloud Function (skip_autocare=true) so Stripe
incremental sync + unified/BI refresh runs immediately after.

Exit codes:
  0 — AutoCare sync succeeded (Stripe function triggered)
  1 — AutoCare sync failed or Stripe function could not be triggered
"""
import os
import sys
import logging
from datetime import datetime

import requests

from bigquery_client import BigQueryClient
from main import sync_autocare_to_bigquery

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
)
logger = logging.getLogger(__name__)


def trigger_stripe_function(function_url: str) -> bool:
    """
    POST to the Stripe Cloud Function with skip_autocare=true.
    The function handles Stripe incremental sync + unified/BI refresh.
    Returns True on HTTP 200, False otherwise.
    """
    logger.info("Triggering Stripe Cloud Function: %s", function_url)
    try:
        resp = requests.post(
            function_url,
            json={"skip_autocare": True},
            timeout=660,  # 11 min — function timeout is 9 min, add buffer
        )
        if resp.status_code == 200:
            logger.info("Stripe function completed successfully: %s", resp.text[:300])
            return True
        else:
            logger.error(
                "Stripe function returned HTTP %d: %s",
                resp.status_code, resp.text[:500],
            )
            return False
    except requests.exceptions.Timeout:
        logger.error("Stripe function timed out after 11 minutes")
        return False
    except Exception as exc:
        logger.error("Failed to trigger Stripe function: %s", exc, exc_info=True)
        return False


def main() -> int:
    logger.info("=" * 60)
    logger.info("AutoCare Cloud Run Job — Starting")
    logger.info("Started at: %s UTC", datetime.utcnow().isoformat())
    logger.info("=" * 60)

    bq_client = BigQueryClient()

    # ── AutoCare sync (streaming, ~1.5h for 700k records) ────────────
    logger.info("\n--- AutoCare Sync ---")
    ac_result = sync_autocare_to_bigquery(bq_client)
    logger.info("AutoCare result: %s", ac_result)

    autocare_ok = ac_result.get("status") in ("success", "partial")
    if not autocare_ok:
        logger.error("AutoCare sync failed: %s", ac_result.get("error"))

    # ── Trigger Stripe Cloud Function ────────────────────────────────
    # Always trigger even if AutoCare had partial failures so Stripe data
    # and unified/BI tables stay fresh regardless.
    stripe_ok = False
    function_url = os.getenv("STRIPE_FUNCTION_URL", "").strip()
    if function_url:
        stripe_ok = trigger_stripe_function(function_url)
    else:
        logger.warning(
            "STRIPE_FUNCTION_URL not set — Stripe sync and unified/BI refresh "
            "will NOT run. Set this env var on the Cloud Run Job."
        )

    # ── Summary ──────────────────────────────────────────────────────
    logger.info("\n" + "=" * 60)
    logger.info("Job Summary")
    logger.info("=" * 60)
    logger.info(
        "  AutoCare : %s (%d records, %d pages)",
        ac_result.get("status"),
        ac_result.get("records_synced", 0),
        ac_result.get("pages", 0),
    )
    if ac_result.get("failed_pages"):
        logger.warning("  Failed pages: %s", ac_result["failed_pages"])
    logger.info(
        "  Stripe   : %s",
        "triggered successfully" if stripe_ok else "not triggered / failed",
    )
    logger.info("Finished at: %s UTC", datetime.utcnow().isoformat())

    return 0 if (autocare_ok and stripe_ok) else 1


if __name__ == "__main__":
    sys.exit(main())
