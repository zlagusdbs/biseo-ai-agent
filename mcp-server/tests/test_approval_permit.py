import httpx
import pytest

from kimbiseo.credentials import Credential
from kimbiseo.approval_client import ApprovalClient
from kimbiseo.errors import AuthExpired
from kimbiseo.permit_client import PermitClient

CRED = Credential("me", "pw")


def approval(handler) -> ApprovalClient:
    return ApprovalClient("https://approval.example.com", CRED, "EXAMPLE", transport=httpx.MockTransport(handler))


def test_approval_login_posts_ad_fields():
    seen = {}

    def handler(request):
        seen.setdefault("paths", []).append(request.url.path)
        if request.method == "POST":
            seen["body"] = request.content.decode()
        return httpx.Response(200, text="{success:true}")

    approval(handler).verify()
    assert seen["paths"] == ["/Login.html", "/Login.cshtml"] and "adid=me" in seen["body"] and "domain=EXAMPLE" in seen["body"]


def test_approval_login_failure_reason():
    with pytest.raises(AuthExpired) as e:
        approval(lambda r: httpx.Response(200, text="{success:false,errors:{reason:'비밀번호 오류<br />다시'}}")).verify()
    assert "비밀번호 오류" in str(e.value) and e.value.code == "AUTH_EXPIRED:approval"


def test_permit_uses_hr_login_with_own_home():
    pages = []

    def handler(request):
        pages.append(request.url.path)
        if request.method == "POST":
            return httpx.Response(200, text="ok")
        if len(pages) == 1:
            return httpx.Response(200, text='<form action="/Account/Authenticate"><input type="password" name="Password">'
                                            '<input name="UserId"></form>')
        return httpx.Response(200, text="<h1>Permit Home</h1>")

    PermitClient("https://permit.example.com", CRED, transport=httpx.MockTransport(handler)).verify()
    assert pages == ["/Permit/Home", "/Account/Authenticate", "/Permit/Home"]


def test_permit_login_failure_is_permit_code():
    login = '<form action="/Account/Authenticate"><input type="password" name="Password"><input name="UserId"></form>'
    with pytest.raises(AuthExpired) as e:
        PermitClient("https://permit.example.com", CRED, transport=httpx.MockTransport(lambda r: httpx.Response(200, text=login))).verify()
    assert e.value.code == "AUTH_EXPIRED:permit"


def test_nested_form_uses_outer_action_like_browser():
    from kimbiseo.hr_client import find_login_form
    page = ('<form id="frmLogin" action="/Account/Authenticate"><form action="/Account/Login?ReturnUrl=x">'
            '<input name="__RequestVerificationToken" type="hidden" value="t"><input name="UserId">'
            '<input name="Password" type="password"></form></form>')
    action, fields = find_login_form(page)
    assert action == "/Account/Authenticate" and fields["__RequestVerificationToken"] == "t"


def test_portal_current_user_and_auth_error():
    from unittest.mock import MagicMock
    from kimbiseo.portal_client import PortalClient
    ok = MagicMock(); ok.status_code = 200; ok.json.return_value = {"d": {"Title": "홍길동", "Email": "a@example.com"}}
    session = MagicMock(); session.headers = {}; session.get.return_value = ok
    assert PortalClient("https://portal.example.com", CRED, session=session).current_user() == {"name": "홍길동", "email": "a@example.com"}
    assert session.get.call_args.args[0] == "https://portal.example.com/_api/web/currentUser"
    denied = MagicMock(); denied.status_code = 401
    session.get.return_value = denied
    with pytest.raises(AuthExpired) as e:
        PortalClient("https://portal.example.com", CRED, session=session).verify()
    assert e.value.code == "AUTH_EXPIRED:portal"
