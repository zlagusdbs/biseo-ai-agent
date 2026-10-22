import httpx
import pytest

from kimbiseo.connections import load_systems, shared_dir
from kimbiseo.credentials import Credential
from kimbiseo.errors import AuthExpired, NetworkUnreachable
from kimbiseo.jira_client import INCOMPLETE_JQL, JiraClient

BASE = "https://jira.example.com"


def client(handler) -> JiraClient:
    return JiraClient(BASE, Credential("user", "pw"), transport=httpx.MockTransport(handler))


def issue(n: int) -> dict:
    return {
        "key": f"PRICING-{n}",
        "fields": {"summary": f"제목 {n}", "status": {"name": "In Progress"}, "priority": {"name": "Major"}, "duedate": None},
    }


def test_load_systems_reads_shared_file():
    systems = load_systems(shared_dir() / "connections.example.json")
    assert [s.id for s in systems] == ["jira", "wiki", "hr", "deploy", "github", "groupware"]
    assert [s.id for s in systems if s.enabled] == ["jira", "wiki", "hr", "deploy", "github"]
    assert {s.id for s in systems if s.group == "ad"} == {"jira", "wiki", "hr", "deploy"}
    assert next(s for s in systems if s.id == "github").auth == "gh"


def test_search_maps_fields_and_truncation():
    def handler(request: httpx.Request):
        assert request.url.params["jql"] == INCOMPLETE_JQL
        assert request.url.params["maxResults"] == "50"
        return httpx.Response(200, json={"total": 120, "issues": [issue(n) for n in range(1, 51)]})

    result = client(handler).search(INCOMPLETE_JQL, 50)
    assert result.total == 120 and result.truncated and len(result.issues) == 50
    assert result.issues[0].url == f"{BASE}/browse/PRICING-1"
    assert result.issues[0].status == "In Progress"


def test_search_not_truncated():
    result = client(lambda r: httpx.Response(200, json={"total": 1, "issues": [issue(1)]})).search("x")
    assert result.total == 1 and not result.truncated


def test_401_raises_auth_expired():
    with pytest.raises(AuthExpired):
        client(lambda r: httpx.Response(401)).verify()


def test_connect_error_raises_network_unreachable():
    def handler(request):
        raise httpx.ConnectError("no route")

    with pytest.raises(NetworkUnreachable):
        client(handler).verify()


def test_uses_basic_auth_header():
    seen = {}

    def handler(request: httpx.Request):
        seen["auth"] = request.headers["Authorization"]
        return httpx.Response(200, json={})

    client(handler).verify()
    assert seen["auth"].startswith("Basic ")
