import httpx
import pytest

from kimbiseo.connections import load_systems, shared_dir
from kimbiseo.credentials import Credential
from kimbiseo.errors import AuthExpired, NetworkUnreachable, RequestRejected
from kimbiseo.jira_client import INCOMPLETE_JQL, IssueDraft, JiraClient

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
    assert [s.id for s in systems] == ["jira", "wiki", "hr", "deploy", "approval", "permit", "github", "microsoft365", "groupware"]
    assert [s.id for s in systems if s.enabled] == ["jira", "wiki", "hr", "deploy", "approval", "permit", "github", "microsoft365"]
    assert {s.company for s in systems} == {"Company A", "Company B"}
    assert next(s for s in systems if s.id == "groupware").company == "Company B"
    assert {s.id for s in systems if s.group == "ad"} == {"jira", "wiki", "hr", "deploy", "approval", "permit"}
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


def create_handler(seen: dict, story_fields=None):
    import json as _json

    def handler(request: httpx.Request):
        path = request.url.path
        if path == "/rest/api/2/issue/createmeta/PRICING/issuetypes":
            return httpx.Response(200, json={"values": [{"id": "3", "name": "Task"}, {"id": "8", "name": "Story"}]})
        if path == "/rest/api/2/issue/createmeta/PRICING/issuetypes/8":
            names = story_fields or [("summary", "Summary"), ("reporter", "Reporter"), ("timetracking", "Time Tracking"),
                                     ("customfield_13401", "Target start "), ("customfield_13402", "Target end "),
                                     ("customfield_10501", "Epic Link ")]
            return httpx.Response(200, json={"values": [{"fieldId": f, "name": n} for f, n in names]})
        if path == "/rest/api/2/myself":
            return httpx.Response(200, json={"name": "user"})
        if path == "/rest/api/2/issue" and request.method == "POST":
            seen["body"] = _json.loads(request.content)["fields"]
            return httpx.Response(201, json={"key": "PRICING-9001"})
        return httpx.Response(404)
    return handler


DRAFT = IssueDraft(project="PRICING", issue_type="story", summary="제목", description="h3. 배경",
                   original_estimate="365d", target_start="2026-10-22", target_end="2026-12-31")


def test_create_issue_maps_custom_fields_by_name():
    seen = {}
    issue = client(create_handler(seen)).create_issue(DRAFT)
    body = seen["body"]
    assert issue.key == "PRICING-9001" and issue.url == f"{BASE}/browse/PRICING-9001"
    assert body["issuetype"] == {"id": "8"} and body["project"] == {"key": "PRICING"}
    assert body["assignee"] == {"name": "user"} and body["reporter"] == {"name": "user"}
    assert body["timetracking"] == {"originalEstimate": "365d"}
    assert body["customfield_13401"] == "2026-10-22" and body["customfield_13402"] == "2026-12-31"
    assert "customfield_10501" not in body   # Epic 은 비었으면 안 보냄


def test_create_issue_skips_fields_project_does_not_have():
    seen = {}
    client(create_handler(seen, story_fields=[("summary", "Summary")])).create_issue(DRAFT)
    assert "timetracking" not in seen["body"] and "customfield_13401" not in seen["body"] and "reporter" not in seen["body"]


def test_create_issue_unknown_type():
    with pytest.raises(RequestRejected) as e:
        client(create_handler({})).create_issue(IssueDraft(project="PRICING", issue_type="개발", summary="s", description=""))
    assert "Task, Story" in str(e.value)


def test_create_issue_rejected_reason():
    def handler(request):
        if request.method == "POST":
            return httpx.Response(400, json={"errorMessages": [], "errors": {"summary": "필수 항목"}})
        return create_handler({})(request)

    with pytest.raises(RequestRejected) as e:
        client(handler).create_issue(DRAFT)
    assert e.value.code == "REJECTED:jira" and "summary: 필수 항목" in str(e.value)


def test_projects_filter():
    rows = [{"key": "PRICING", "name": "Promotion"}, {"key": "PDB", "name": "Pricing DB"}, {"key": "X", "name": "Other"}]
    c = client(lambda r: httpx.Response(200, json=rows))
    assert [p["key"] for p in c.projects("pricing")] == ["PRICING", "PDB"]
    assert len(c.projects()) == 3


def test_add_worklog_posts_started_and_seconds():
    import json as _json
    seen = {}

    def handler(request):
        seen["path"], seen["body"] = request.url.path, _json.loads(request.content)
        return httpx.Response(201, json={"id": 77})

    result = client(handler).add_worklog("MYPROJ-100", "2026-10-22T10:00:00.000+0900", 3600, "회의")
    assert seen["path"] == "/rest/api/2/issue/MYPROJ-100/worklog"
    assert seen["body"] == {"started": "2026-10-22T10:00:00.000+0900", "timeSpentSeconds": 3600, "comment": "회의"}
    assert result["id"] == "77"


def test_add_worklog_rejects_zero():
    with pytest.raises(RequestRejected):
        client(lambda r: httpx.Response(201, json={})).add_worklog("A-1", "2026-10-22T10:00:00.000+0900", 0)


def test_my_worklogs_filters_me_and_date():
    def handler(request):
        path = request.url.path
        if path == "/rest/api/2/myself":
            return httpx.Response(200, json={"name": "me"})
        if path == "/rest/api/2/search":
            assert 'worklogDate = "2026-10-22"' in request.url.params["jql"]
            return httpx.Response(200, json={"issues": [{"key": "A-1", "fields": {"summary": "회의"}}]})
        return httpx.Response(200, json={"worklogs": [
            {"author": {"name": "me"}, "started": "2026-10-22T13:00:00.000+0900", "timeSpentSeconds": 1800},
            {"author": {"name": "me"}, "started": "2026-10-22T10:00:00.000+0900", "timeSpentSeconds": 3600, "comment": "c"},
            {"author": {"name": "other"}, "started": "2026-10-22T10:00:00.000+0900", "timeSpentSeconds": 999},
            {"author": {"name": "me"}, "started": "2026-10-21T10:00:00.000+0900", "timeSpentSeconds": 999},
        ]})

    result = client(handler).my_worklogs("2026-10-22")
    assert result["totalSeconds"] == 5400
    assert [(w["started"], w["seconds"]) for w in result["worklogs"]] == [("10:00", 3600), ("13:00", 1800)]
