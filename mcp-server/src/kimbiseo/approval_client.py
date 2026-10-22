"""사내 Approval (전자결재). 로그인 화면(/Login.html)을 먼저 열어 세션을 받은 뒤, ExtJS 폼처럼 /Login.cshtml 로
adid·pwd·domain 을 POST 한다. 응답은 JSON 이 아니라 JS 객체 글자다: {success:false,errors:{reason:'...'}}
(세션 없이 보내면 500). 지금은 연결 확인(로그인)만 한다.
"""

import re

import httpx

from .credentials import Credential
from .errors import AuthExpired, KimbiseoError, NetworkUnreachable

SYSTEM = "approval"
TIMEOUT_SECONDS = 15.0


class ApprovalClient:
    def __init__(self, base_url: str, cred: Credential, domain: str = "", transport: httpx.BaseTransport | None = None):
        self.base_url = base_url.rstrip("/")
        self.cred = cred
        self.domain = domain   # 로그인 화면의 도메인 선택값 (connections 파일의 loginDomain)
        self._client = httpx.Client(base_url=self.base_url, timeout=TIMEOUT_SECONDS, transport=transport,
                                    follow_redirects=True)

    def verify(self) -> None:
        try:
            self._client.get("/Login.html")
            response = self._client.post("/Login.cshtml",
                                         data={"adid": self.cred.username, "pwd": self.cred.secret, "domain": self.domain},
                                         headers={"X-Requested-With": "XMLHttpRequest",
                                                  "Referer": self.base_url + "/Login.html"})
        except httpx.TransportError as e:
            raise NetworkUnreachable(SYSTEM, str(e)) from e
        if response.status_code in (401, 403):
            raise AuthExpired(SYSTEM, f"HTTP {response.status_code}")
        if response.status_code >= 500:
            raise KimbiseoError(SYSTEM, f"HTTP {response.status_code}")
        if re.search(r"""["']?success["']?\s*:\s*true""", response.text):
            return
        if re.search(r"""["']?success["']?\s*:\s*false""", response.text):
            reason = re.search(r"""reason["']?\s*:\s*["']([^"']*)""", response.text)
            raise AuthExpired(SYSTEM, re.sub(r"<br\s*/?>", " ", reason.group(1)) if reason else "로그인 실패")
        raise KimbiseoError(SYSTEM, "로그인 응답을 읽지 못했어요")
