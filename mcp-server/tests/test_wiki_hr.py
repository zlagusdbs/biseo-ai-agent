import httpx
import pytest

from kimbiseo import server
from kimbiseo.credentials import Credential, save
from kimbiseo.hr_client import HrClient, as_date, find_login_form, looks_like_login
from kimbiseo.errors import AuthExpired
from kimbiseo.wiki_client import WikiClient, cql_for, html_to_text

CRED = Credential("user", "pw")


def test_cql_escapes_quotes():
    assert cql_for('장바구니 "쿠폰"') == 'siteSearch ~ "장바구니 \\"쿠폰\\"" AND type = page'


def test_wiki_search_maps_results():
    def handler(request):
        assert request.url.path == "/rest/api/search"
        return httpx.Response(200, json={"results": [{
            "content": {"id": "123", "title": "쿠폰 설계"},
            "url": "/pages/viewpage.action?pageId=123",
            "excerpt": "장바구니 <b>쿠폰</b>",
            "resultGlobalContainer": {"title": "DISCOUNTCOUPON"},
        }]})

    pages = WikiClient("https://wiki.example.com", CRED, httpx.MockTransport(handler)).search("쿠폰")
    assert pages[0].id == "123" and pages[0].space == "DISCOUNTCOUPON"
    assert pages[0].url == "https://wiki.example.com/pages/viewpage.action?pageId=123"
    assert pages[0].excerpt == "장바구니 쿠폰"


def test_wiki_page_text_truncated():
    body = "<p>" + "가" * 9000 + "</p>"
    handler = lambda r: httpx.Response(200, json={"id": "1", "title": "t", "body": {"storage": {"value": body}},
                                                  "space": {"name": "S"}, "_links": {"webui": "/x"}})
    page = WikiClient("https://w", CRED, httpx.MockTransport(handler)).get_page("1")
    assert page["truncated"] and len(page["text"]) == 8000


def test_html_to_text():
    assert html_to_text("<p>a&amp;b</p><p>c</p>") == "a&b\nc"


LOGIN_PAGE = """<html><form action="/Account/Authenticate" method="post">
<input type="hidden" name="__RequestVerificationToken" value="tok">
<input type="text" name="UserId"><input type="password" name="Password">
<input type="submit" value="로그인"></form></html>"""


def test_find_login_form_keeps_hidden_fields():
    action, fields = find_login_form(LOGIN_PAGE)
    assert action == "/Account/Authenticate"
    assert fields == {"__RequestVerificationToken": "tok", "UserId": "", "Password": ""}


def test_looks_like_login():
    assert looks_like_login("https://hr/Account/Login?ReturnUrl=%2F", "")
    assert looks_like_login("https://hr/", LOGIN_PAGE)
    assert not looks_like_login("https://hr/", "<title>HR-로그인</title><a href='/Account/Login'>")


def hr_transport(login_ok: bool):
    state = {"logged": False}

    def handler(request: httpx.Request):
        if request.method == "POST" and request.url.path == "/Account/Authenticate":
            body = request.content.decode()
            assert "__RequestVerificationToken=tok" in body and "UserId=user" in body
            state["logged"] = login_ok
            return httpx.Response(200, text="ok")
        if request.url.path == "/":
            return httpx.Response(200, text="<html>home</html>" if state["logged"] else LOGIN_PAGE)
        if request.url.path == "/Comm/GetHolidayList":
            assert request.headers["Referer"].endswith("/VacaReg/VacaRegMain")
            return httpx.Response(200, json={"Success": True, "Result": [
                {"Holiday": "/Date(1791126000000)/", "HolidayName": "개천절"}]})
        return httpx.Response(404)

    return httpx.MockTransport(handler)


def test_hr_login_and_holidays():
    rows = HrClient("https://hr.example.com", CRED, hr_transport(True)).holidays()
    assert rows[0]["name"] == "개천절" and rows[0]["date"].startswith("2026-10-")


def test_hr_login_failure_raises_auth_expired():
    with pytest.raises(AuthExpired):
        HrClient("https://hr.example.com", CRED, hr_transport(False)).verify()


def test_as_date():
    assert as_date("plain") == "plain"


def test_new_tools_not_connected():
    assert server.wiki_search("x") == {"error": "NOT_CONNECTED:wiki"}
    assert server.hr_holidays() == {"error": "NOT_CONNECTED:hr"}
