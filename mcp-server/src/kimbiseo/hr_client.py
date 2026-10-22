"""사내 HR (인사·근태) 조회. ASP.NET 폼 로그인 후 쿠키 세션으로 JSON API 를 호출한다.

API 는 모두 POST + JSON 바디 + 소속 페이지 Referer 이고, 응답은 {Success, Message, Result} 봉투다.
"""

import datetime
import re
from html.parser import HTMLParser
from urllib.parse import urljoin

import httpx

from .credentials import Credential
from .errors import AuthExpired, KimbiseoError, NetworkUnreachable

SYSTEM = "hr"
TIMEOUT_SECONDS = 15.0
VACATION_PAGE = "/VacaReg/VacaRegMain"
FLEXWORK_PAGE = "/Flexwork/Edit"
INIT_RE = re.compile(r"FlexworkEdit\.Init\s*\(\s*'([^']*)'\s*,\s*'([^']*)'")
JSON_DATE_RE = re.compile(r"/Date\((-?\d+)")


class _LoginFormParser(HTMLParser):
    """비밀번호 입력칸이 있는 form 의 action 과 hidden 필드를 찾는다.

    브라우저처럼 form 안의 form 은 무시한다 (Permit 로그인 화면은 form 이 겹쳐 있고, 바깥 form 으로 제출된다).
    """

    def __init__(self):
        super().__init__()
        self.forms: list[tuple[str, dict[str, str], bool]] = []
        self._current: tuple[str, dict[str, str], list[bool]] | None = None

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "form":
            if self._current is None:
                self._current = (a.get("action") or "", {}, [False])
        elif tag == "input" and self._current is not None:
            kind = (a.get("type") or "text").lower()
            if kind == "password":
                self._current[2][0] = True
            if a.get("name") and kind not in ("submit", "button"):
                self._current[1][a["name"]] = a.get("value") or ""

    def handle_endtag(self, tag):
        if tag == "form" and self._current is not None:
            action, fields, has_pw = self._current
            self.forms.append((action, fields, has_pw[0]))
            self._current = None


def find_login_form(page: str) -> tuple[str, dict[str, str]] | None:
    parser = _LoginFormParser()
    parser.feed(page)
    for action, fields, has_password in parser.forms:
        if has_password:
            return action, fields
    return None


def looks_like_login(url: str, body: str) -> bool:
    return "/account/login" in url.lower() or 'type="password"' in body[:20000] or "type='password'" in body[:20000]


def as_date(value) -> str:
    """ASP.NET `/Date(ms)/` → yyyy-MM-dd (서버 KST 자정 기준이라 로컬 시간대로 읽는다)."""
    m = JSON_DATE_RE.search(str(value))
    if not m:
        return str(value or "")
    return datetime.datetime.fromtimestamp(int(m.group(1)) / 1000).strftime("%Y-%m-%d")


class HrClient:
    """Permit 처럼 같은 방식(ASP.NET 폼 로그인)의 사내 시스템은 이 클래스를 이어받아 system·home 만 바꾼다."""
    system = SYSTEM
    home = "/"   # 로그인 확인에 쓰는 첫 화면

    def __init__(self, base_url: str, cred: Credential, transport: httpx.BaseTransport | None = None):
        self.base_url = base_url.rstrip("/")
        self.cred = cred
        self._client = httpx.Client(base_url=self.base_url, timeout=TIMEOUT_SECONDS, transport=transport,
                                    follow_redirects=True)
        self._logged_in = False

    def verify(self) -> None:
        self._login()

    def holidays(self) -> list[dict]:
        rows = self._call("/Comm/GetHolidayList", {}, VACATION_PAGE) or []
        return [{"date": as_date(r.get("Holiday")), "name": r.get("HolidayName", "")} for r in rows]

    def flexwork_week(self, date: str) -> dict:
        page = self._request("GET", FLEXWORK_PAGE).text
        m = INIT_RE.search(page)
        if not m:
            raise KimbiseoError(SYSTEM, "사번을 찾지 못했어요")
        staff_no = m.group(2)
        week = self._call("/Flexwork/GetWeekInfoByDate", {"reqDate": date}, FLEXWORK_PAGE) or {}
        if week.get("WeekSeq") is None:
            return {"date": date, "days": []}
        flex = self._call("/Flexwork/GetFlexworkByWeekSeq",
                          {"weekSeq": week["WeekSeq"], "staffNo": staff_no, "isSyncVaction": False}, FLEXWORK_PAGE) or {}
        days = [{
            "date": as_date(d.get("DetailDate")),
            "start": d.get("TaskStartTime"),
            "end": d.get("TaskEndTime"),
            "hours": d.get("TaskTime"),
            "vacation": d.get("VacationType") or None,
        } for d in (flex.get("Detail") or [])]
        return {"weekStart": as_date(week.get("WeekStartDate")), "days": days}

    # 내부

    def _login(self) -> None:
        page = self._request("GET", self.home, login=False)
        if not looks_like_login(str(page.url), page.text):
            self._logged_in = True
            return
        form = find_login_form(page.text)
        if form is None:
            raise KimbiseoError(self.system, "로그인 화면을 찾지 못했어요")
        action, fields = form
        fields["UserId"] = self.cred.username
        fields["Password"] = self.cred.secret
        self._request("POST", urljoin(str(page.url), action), data=fields, login=False)
        check = self._request("GET", self.home, login=False)
        if looks_like_login(str(check.url), check.text):
            raise AuthExpired(self.system, "로그인 실패")
        self._logged_in = True

    def _call(self, path: str, body: dict, referer_path: str):
        response = self._request("POST", path, json=body, headers={"Referer": self.base_url + referer_path,
                                                                    "X-Requested-With": "XMLHttpRequest"})
        if "json" not in response.headers.get("content-type", ""):
            raise AuthExpired(self.system, "JSON 이 아닌 응답 (세션 만료)")
        data = response.json()
        if not data.get("Success"):
            raise KimbiseoError(self.system, data.get("Message") or "Success=false")
        result = data.get("Result")
        if isinstance(result, dict) and result and all(isinstance(v, dict) for v in result.values()):
            return list(result.values())
        return result

    def _request(self, method: str, url: str, login: bool = True, **kwargs) -> httpx.Response:
        if login and not self._logged_in:
            self._login()
        try:
            response = self._client.request(method, url, **kwargs)
        except httpx.TransportError as e:
            raise NetworkUnreachable(self.system, str(e)) from e
        if response.status_code in (401, 403):
            raise AuthExpired(self.system, f"HTTP {response.status_code}")
        response.raise_for_status()
        return response
