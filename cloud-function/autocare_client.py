"""
AutoCare API client for v1/marketing/tiers and v1/marketing/data.
Uses api/login with email/password to obtain JWT, then Bearer token for marketing endpoints.

Production API: https://memberships.autocarepr.com/api
"""
import logging
import time
from typing import Dict, Iterator, List, Any, Optional

import requests

logger = logging.getLogger(__name__)

BASE_URL  = "https://memberships.autocarepr.com/api"
LOGIN_URL = f"{BASE_URL}/login"
TIERS_URL = f"{BASE_URL}/v1/marketing/tiers"
DATA_URL  = f"{BASE_URL}/v1/marketing/data"
STRIPE_CUSTOMERS_URL = f"{BASE_URL}/v1/marketing/stripe-customers"

# Pagination / retry / pressure-relief settings
_PAGE_SIZE   = 1000
_STRIPE_LIMIT = 1000  # max per request for stripe-customers (API doc: limit default 100, max 1000)
_MAX_RETRIES = 3
_RETRY_SLEEP = 3    # seconds between retry attempts on transient errors
_PAGE_SLEEP  = 0.3  # seconds between consecutive page fetches to reduce server pressure

# Transient errors that warrant a retry.
# SSLEOFError is caught as SSLError — server drops the TLS connection under load.
_RETRYABLE = (
    requests.exceptions.ChunkedEncodingError,
    requests.exceptions.ConnectionError,
    requests.exceptions.Timeout,
    requests.exceptions.SSLError,
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

        Handles two distinct failure modes:
        - Transient network errors (SSL EOF, connection drop, timeout): retry with
          the same token after a short sleep.
        - 401 Unauthorized: the JWT has expired mid-job (common after ~1h of
          continuous fetching). Clear the cached token so _get_token() re-logs in,
          then retry immediately without sleeping.

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

                # JWT expired mid-job — re-authenticate and retry immediately.
                if resp.status_code == 401:
                    logger.warning(
                        "AutoCare 401 on attempt %d/%d (JWT likely expired) — "
                        "clearing token and re-authenticating ...",
                        attempt, _MAX_RETRIES,
                    )
                    self._token = None  # force _get_token() to login again
                    if attempt == _MAX_RETRIES:
                        raise RuntimeError(
                            f"AutoCare returned 401 after {_MAX_RETRIES} re-auth "
                            f"attempts for {url}?{params}"
                        )
                    continue  # no sleep — just re-login and retry

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
        Tiers are a small reference table; all pages are collected and returned.
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
        Fetch ALL v1/marketing/data pages into memory.
        Only use this for small datasets. For 700k+ records use
        stream_marketing_data_pages() instead.
        """
        all_records: List[Dict] = []
        for page_batch in self.stream_marketing_data_pages():
            all_records.extend(page_batch)
        return all_records

    def stream_marketing_data_pages(self) -> Iterator[List[Dict[str, Any]]]:
        """
        Generator that yields one page of marketing data at a time.

        Never accumulates the full dataset in RAM — peak memory is bounded
        to _PAGE_SIZE records (~2–3 MB) regardless of total dataset size.

        Includes _PAGE_SLEEP between fetches to reduce sustained load on
        the AutoCare server and prevent SSL EOF connection drops.

        Usage:
            for page in client.stream_marketing_data_pages():
                process(page)   # then let page be garbage-collected
        """
        page = 1

        while True:
            params = {
                "page": page,
                "per_page": _PAGE_SIZE,
                "includeOnlyServiceType": "true",
            }
            logger.info("AutoCare marketing data: fetching page %d ...", page)

            body = self._get_with_retry(DATA_URL, params)
            batch = self._extract_list(body, "stream_marketing_data_pages")

            if not batch:
                logger.info("AutoCare marketing data: page %d empty — done.", page)
                break

            logger.info(
                "AutoCare marketing data: page %d → %d records",
                page, len(batch),
            )
            yield batch

            if len(batch) < _PAGE_SIZE:
                logger.info(
                    "AutoCare marketing data: page %d is the last page (%d < %d).",
                    page, len(batch), _PAGE_SIZE,
                )
                break

            page += 1
            time.sleep(_PAGE_SLEEP)

    def get_stripe_customers(self) -> List[Dict[str, Any]]:
        """
        Fetch all Stripe-linked customers from v1/marketing/stripe-customers.
        Uses cursor-based pagination (limit + nextCursor). Returns full list in memory.
        Requires API_ADMIN role. ~11k records typically; runs in seconds.
        """
        all_records: List[Dict] = []
        cursor: Optional[str] = None
        page_num = 0

        while True:
            params: Dict[str, Any] = {"limit": _STRIPE_LIMIT}
            if cursor:
                params["cursor"] = cursor

            logger.info("AutoCare stripe-customers: fetching page %s ...", page_num + 1)
            body = self._get_with_retry(STRIPE_CUSTOMERS_URL, params)
            batch = self._extract_list(body, "get_stripe_customers")
            next_cursor = body.get("nextCursor") if isinstance(body, dict) else None

            if not batch:
                logger.info("AutoCare stripe-customers: page empty — done.")
                break

            all_records.extend(batch)
            page_num += 1
            logger.info(
                "AutoCare stripe-customers: page %d → %d records (total %d)",
                page_num, len(batch), len(all_records),
            )

            if not next_cursor:
                break
            cursor = next_cursor
            time.sleep(_PAGE_SLEEP)

        logger.info("AutoCare stripe-customers: fetched %d total", len(all_records))
        return all_records
