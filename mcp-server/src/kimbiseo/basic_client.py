"""사내 계정 Basic 인증을 쓰는 시스템(Jira, Wiki)의 공통 HTTP 처리."""

import httpx

from .credentials import Credential
from .errors import AuthExpired, NetworkUnreachable

TIMEOUT_SECONDS = 10.0


class BasicClient:
    system = ""

    def __init__(self, base_url: str, cred: Credential, transport: httpx.BaseTransport | None = None):
        self.base_url = base_url.rstrip("/")
        self._client = httpx.Client(
            base_url=self.base_url,
            auth=(cred.username, cred.secret),
            timeout=TIMEOUT_SECONDS,
            transport=transport,
            headers={"Accept": "application/json"},
        )

    def _get(self, path: str, params: dict | None = None) -> httpx.Response:
        try:
            response = self._client.get(path, params=params)
        except httpx.TransportError as e:
            raise NetworkUnreachable(self.system, str(e)) from e
        if response.status_code in (401, 403):
            raise AuthExpired(self.system, f"HTTP {response.status_code}")
        response.raise_for_status()
        return response
