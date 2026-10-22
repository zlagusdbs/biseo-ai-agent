"""사내 포털 Portal (SharePoint). AD 계정으로 NTLM 인증한다. 지금은 연결 확인(로그인한 사용자 조회)만 한다."""

import requests
from requests_ntlm import HttpNtlmAuth

from .credentials import Credential
from .errors import AuthExpired, KimbiseoError, NetworkUnreachable

SYSTEM = "portal"
TIMEOUT_SECONDS = 30


class PortalClient:
    def __init__(self, base_url: str, cred: Credential, session: requests.Session | None = None):
        self.base_url = base_url.rstrip("/")
        self._session = session or requests.Session()
        self._session.auth = HttpNtlmAuth(cred.username, cred.secret)
        self._session.headers["Accept"] = "application/json;odata=verbose"

    def verify(self) -> None:
        self.current_user()

    def current_user(self) -> dict:
        try:
            response = self._session.get(f"{self.base_url}/_api/web/currentUser", timeout=TIMEOUT_SECONDS)
        except requests.RequestException as e:
            raise NetworkUnreachable(SYSTEM, str(e)) from e
        if response.status_code in (401, 403):
            raise AuthExpired(SYSTEM, f"HTTP {response.status_code}")
        if response.status_code >= 400:
            raise KimbiseoError(SYSTEM, f"HTTP {response.status_code}")
        data = response.json().get("d", {})
        return {"name": data.get("Title", ""), "email": data.get("Email", "")}
