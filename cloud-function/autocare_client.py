"""
AutoCare API client for v1/marketing/tiers and v1/marketing/data.
Uses api/login with email/password to obtain JWT, then Bearer token for marketing endpoints.

Production API: https://memberships.autocarepr.com/api
"""
import logging
import time
from typing import Dict, List, Any, Optional

import requests

logger = logging.getLogger(__name__)

BASE_URL  = "https://memberships.autocarepr.com/api"
LOGIN_URL = f"{BASE_URL}/login"
TIERS_URL = f"{BASE_URL}/v1/marketing/tiers"
DATA_URL  = f"{BASE_URL}/v1/marketing/data"

# Pagination / retry settings
_PAGE_SIZE   = 1000
_MAX_RETRIES = 3
_RETRY_SLEEP = 3  # seconds between retry attempts

# Transient errors that warrant a retry
_RETRYABLE = (
    requests.exceptions.ChunkedEncodingError,
    requests.exceptions.ConnectionError,
    requests.exceptions.Timeout,
)


class AutoCareClient:
    """Client for AutoCare marketing API (login + tiers + marketing data)."""

    def __init__(
        self,
        email: Optional[str] = None,
        password: Optional[str] = None,
    ):
        self.email    = email
        self.password = password
        self._token: Optional[str] = None

    # ------------------------------------------------------------------
    # Auth
    # ------------------------------------------------------------------

    def _get_token(self) -> str:
        if self._token:
            return self._token
        if not self.email or not self.password:
            raise ValueError("AutoCare credentials (email, password) required")
        resp = requests.post(
            LOGIN_URL,
            json={"email": self.email, "password": self.password},
            timeout=30,
        )
        if resp.status_code not in (200, 201):
            raise RuntimeError(
                f"AutoCare login failed: {resp.status_code} - {resp.text[:500]}"
            )
        data = resp.json()
        token = (
            data.get("token")
            or data.get("access_token")
            or data.get("accessToken")
            or data.get("jwt")
        )
        if not token:
            raise RuntimeError("AutoCare login response had no token")
        self._token = token
        logger.info("AutoCare login successful")
        return self._token

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _get_with_retry(self, url: str, params: Dict) -> Any:
        """
        GET a single page with up to _MAX_RETRIES attempts on transient errors.
        Returns the parsed JSON body, or raises on unrecoverable failure.
        """
        for attempt in range(1, _MAX_RETRIES + 1):
            try:
                resp = requests.get(
                    url,
                    headers={"Authorization": f"Bearer {self._get_token()}"},
                    params=params,
                    timeout=60,
                )
                resp.raise_for_status()
                return resp.json()
            except _RETRYABLE as exc:
                if attempt == _MAX_RETRIES:
                    raise
                logger.warning(
                    "AutoCare request to %s attempt %d/%d failed (%s: %s). "
                    "Retrying in %ds...",
                    url, attempt, _MAX_RETRIES, type(exc).__name__, exc, _RETRY_SLEEP,
                )
                time.sleep(_RETRY_SLEEP)

    @staticmethod
    def _extract_list(body: Any, endpoint_label: str) -> List[Dict]:
        """Pull the data list out of a paginated or plain list response."""
        if isinstance(body, list):
            return body
        if isinstance(body, dict):
            if "data" in body:
                return body["data"] if isinstance(body["data"], list) else []
            logger.warning(
                "%s: unexpected response keys=%s", endpoint_label, list(body.keys())
            )
        return []

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def get_tiers(self) -> List[Dict[str, Any]]:
        """
        Fetch v1/marketing/tiers with full pagination.
        Returns the combined list of tier objects across all pages.
        """
        all_tiers: List[Dict] = []
        page = 1

        while True:
            params = {"page": page, "per_page": _PAGE_SIZE}
            logger.info("AutoCare tiers: fetching page %d ...", page)

            body = self._get_with_retry(TIERS_URL, params)
            batch = self._extract_list(body, "get_tiers")

            if not batch:
                logger.info("AutoCare tiers: page %d empty — done.", page)
                break

            all_tiers.extend(batch)
            logger.info(
                "AutoCare tiers: page %d → %d records (running total: %d)",
                page, len(batch), len(all_tiers),
            )

            if len(batch) < _PAGE_SIZE:
                logger.info(
                    "AutoCare tiers: page %d is the last page (%d < %d).",
                    page, len(batch), _PAGE_SIZE,
                )
                break

            page += 1

        logger.info("AutoCare tiers: fetched %d total", len(all_tiers))
        return all_tiers

    def get_marketing_data(self) -> List[Dict[str, Any]]:
        """
        Fetch v1/marketing/data with full pagination and per-page retry.

        Uses includeOnlyServiceType=true to match the production data scope
        used in manual tests. Iterates pages of _PAGE_SIZE until the API
        returns a partial page, signalling the final page.

        Returns the combined list of customer/session records.
        """
        all_records: List[Dict] = []
        page = 1

        while True:
            params = {
                "page": page,
                "per_page": _PAGE_SIZE,
                "includeOnlyServiceType": "true",
            }
            logger.info("AutoCare marketing data: fetching page %d ...", page)

            body = self._get_with_retry(DATA_URL, params)
            batch = self._extract_list(body, "get_marketing_data")

            if batch is None:
                logger.error(
                    "AutoCare marketing data: page %d failed after %d attempts. Stopping.",
                    page, _MAX_RETRIES,
                )
                break

            if not batch:
                logger.info("AutoCare marketing data: page %d empty — done.", page)
                break

            all_records.extend(batch)
            logger.info(
                "AutoCare marketing data: page %d → %d records (running total: %d)",
                page, len(batch), len(all_records),
            )

            if len(batch) < _PAGE_SIZE:
                logger.info(
                    "AutoCare marketing data: page %d is the last page (%d < %d).",
                    page, len(batch), _PAGE_SIZE,
                )
                break

            page += 1

        if len(all_records) == 0:
            logger.warning(
                "AutoCare marketing data: 0 records returned across all pages. "
                "Check credentials and that the production API has data."
            )
        else:
            logger.info("AutoCare marketing data: fetched %d total records", len(all_records))

        return all_records
