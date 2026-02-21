"""
AutoCare API client for v1/marketing/tiers and v1/marketing/data.
Uses api/login with email/password to obtain JWT, then Bearer token for marketing endpoints.
"""
import logging
from typing import Dict, List, Any, Optional

import requests

logger = logging.getLogger(__name__)

BASE_URL = "https://autocare-memberships-832d3.ondigitalocean.app/api"
LOGIN_URL = f"{BASE_URL}/login"
TIERS_URL = f"{BASE_URL}/v1/marketing/tiers"
DATA_URL = f"{BASE_URL}/v1/marketing/data"


class AutoCareClient:
    """Client for AutoCare marketing API (login + tiers + marketing data)."""

    def __init__(
        self,
        email: Optional[str] = None,
        password: Optional[str] = None,
    ):
        self.email = email
        self.password = password
        self._token: Optional[str] = None

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

    def get_tiers(self) -> List[Dict[str, Any]]:
        """Fetch v1/marketing/tiers. Returns list of tier objects."""
        token = self._get_token()
        resp = requests.get(
            TIERS_URL,
            headers={"Authorization": f"Bearer {token}"},
            timeout=60,
        )
        resp.raise_for_status()
        body = resp.json()
        if isinstance(body, dict) and "data" in body:
            return body["data"]
        if isinstance(body, list):
            return body
        return []

    def get_marketing_data(self) -> List[Dict[str, Any]]:
        """Fetch v1/marketing/data. Returns list of mixed customer/session records."""
        token = self._get_token()
        resp = requests.get(
            DATA_URL,
            headers={"Authorization": f"Bearer {token}"},
            timeout=120,
        )
        resp.raise_for_status()
        body = resp.json()
        if isinstance(body, dict) and "data" in body:
            return body["data"]
        if isinstance(body, list):
            return body
        return []
