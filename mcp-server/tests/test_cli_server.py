import io
import json

from kimbiseo import cli, credentials, server
from kimbiseo.credentials import Credential, is_expired, load, mark_expired, save
from kimbiseo.errors import AuthExpired, NetworkUnreachable


def run(argv, stdin_text="", verifiers=None):
    out = io.StringIO()
    code = cli.main(argv, stdin=io.StringIO(stdin_text), stdout=out, verifiers=verifiers)
    return code, json.loads(out.getvalue())


def ok(system, cred):
    pass


def fail_auth(system, cred):
    raise AuthExpired(system.id)


def fail_net(system, cred):
    raise NetworkUnreachable(system.id)


def test_connect_success_saves():
    code, out = run(["connect", "jira"], "user\npw\n", {"jira": ok})
    assert code == 0 and out == [{"system": "jira", "status": "connected", "message": "연결됐어요"}]
    assert load("jira") == Credential("user", "pw")


def test_connect_auth_failed_does_not_save():
    code, out = run(["connect", "jira"], "user\nbad\n", {"jira": fail_auth})
    assert code == 1 and out[0]["status"] == "auth_failed"
    assert load("jira") is None


def test_connect_network_unreachable_does_not_save():
    code, out = run(["connect", "jira"], "user\npw\n", {"jira": fail_net})
    assert code == 1 and out[0]["status"] == "network_unreachable"
    assert load("jira") is None


def test_password_with_spaces_and_hangul():
    seen = {}
    run(["connect", "jira"], "user\np w 한글!\n", {"jira": lambda s, c: seen.setdefault("c", c)})
    assert seen["c"] == Credential("user", "p w 한글!")


def test_group_ad_skips_disabled():
    code, out = run(["connect", "--group", "ad"], "user\npw\n", {"jira": ok})
    assert code == 0
    assert {r["system"]: r["status"] for r in out} == {"jira": "connected", "wiki": "unavailable", "hr": "unavailable", "deploy": "unavailable"}


def test_bad_input_returns_2():
    code, out = run(["connect", "jira"], "onlyuser\n", {"jira": ok})
    assert code == 2 and "error" in out


def test_status_reports_states(monkeypatch):
    monkeypatch.setattr(cli.github_client, "is_logged_in", lambda base_url: True)
    save("jira", Credential("user", "pw"))
    mark_expired("jira")
    code, out = run(["status"], verifiers={"jira": ok})
    states = {r["system"]: r["status"] for r in out}
    assert states == {"jira": "expired", "wiki": "unavailable", "hr": "unavailable", "deploy": "unavailable",
                      "github": "connected", "groupware": "unavailable"}


def test_tool_not_connected():
    assert server.jira_search("x") == {"error": "NOT_CONNECTED:jira"}


def test_tool_auth_expired_marks(monkeypatch):
    save("jira", Credential("user", "pw"))

    def boom(self, jql, max_results=50):
        raise AuthExpired("jira")

    monkeypatch.setattr(server.JiraClient, "search", boom)
    assert server.jira_search("x") == {"error": "AUTH_EXPIRED:jira"}
    assert is_expired("jira")


def test_tool_success_shape(monkeypatch):
    from kimbiseo.jira_client import Issue, SearchResult

    save("jira", Credential("user", "pw"))
    monkeypatch.setattr(server.JiraClient, "search", lambda self, jql, max_results=50: SearchResult(
        [Issue("PRICING-1", "제목", "In Progress", "Major", None, "u")], 1, False))
    out = server.jira_search("x")
    assert set(out) == {"total", "truncated", "issues"}
    assert out["issues"][0]["key"] == "PRICING-1"


def test_github_rows_from_search():
    from kimbiseo.github_client import pull_request_rows
    rows = pull_request_rows({"items": [{"id": 7, "number": 1290, "title": "장쿠 보정", "user": {"login": "kim"},
                                         "html_url": "https://gh/x/pull/1290", "updated_at": "2026-10-22T10:42:00Z",
                                         "repository_url": "https://gh/api/v3/repos/my-org/sample-api"}]})
    assert rows == [{"id": 7, "repo": "my-org/sample-api", "number": 1290, "title": "장쿠 보정", "author": "kim",
                     "url": "https://gh/x/pull/1290", "updated": "2026-10-22T10:42"}]


def test_deploy_client_maps_release():
    import httpx
    from kimbiseo.deploy_client import DeployClient
    handler = lambda r: httpx.Response(200, json=[{"id": 1, "domainId": 2, "summary": "s", "status": "Open",
                                                  "creatingUser": {"name": "kim"}, "created": "2026-10-22T10:00:00"}])
    rows = DeployClient("http://deploy", Credential("u", "p"), httpx.MockTransport(handler)).approvals()
    assert rows[0]["creatingUser"] == "kim" and rows[0]["created"] == "2026-10-22T10:00"


def test_github_tool_not_logged_in(monkeypatch):
    monkeypatch.setattr(server.github_client, "is_logged_in", lambda base_url: False)
    assert server.github_review_requests() == {"error": "NOT_CONNECTED:github"}


def test_events_list_and_github_my_reviews(monkeypatch):
    from kimbiseo import events
    code, out = run(["events", "list"])
    assert code == 0 and "github.my_pr_approved" in [e["id"] for e in out]
    monkeypatch.setattr(events.github_client, "is_logged_in", lambda base_url: True)
    monkeypatch.setattr(events.github_client, "me", lambda base_url: "me")
    monkeypatch.setattr(events.github_client, "my_open_prs", lambda base_url: [
        {"id": 1, "repo": "my-org/sample-api", "number": 5, "title": "기능", "author": "me", "url": "u", "updated": ""}])
    monkeypatch.setattr(events.github_client, "reviews", lambda base_url, repo, number: [
        {"id": 10, "state": "APPROVED", "user": {"login": "kim"}, "html_url": "r10"},
        {"id": 11, "state": "COMMENTED", "user": {"login": "me"}},
        {"id": 12, "state": "CHANGES_REQUESTED", "user": {"login": "lee"}}])
    monkeypatch.setattr(events.github_client, "issue_comments", lambda base_url, repo, number: [
        {"id": 20, "user": {"login": "park"}, "body": "확인 부탁\n드려요"}])
    approved = events.fetch("github.my_pr_approved")
    assert [i["key"] for i in approved] == ["review:10"] and approved[0]["title"] == "승인 · sample-api #5"
    feedback = events.fetch("github.my_pr_feedback")
    assert [i["key"] for i in feedback] == ["review:12", "comment:20"]
    assert feedback[1]["summary"] == "park: 확인 부탁 드려요"


def test_events_not_connected():
    code, out = run(["events", "deploy.approval_requested"])
    assert code == 1 and out["error"] == "NOT_CONNECTED:deploy"


def test_deploy_status_key_changes_with_status(monkeypatch):
    from kimbiseo import events
    save("deploy", Credential("u", "p"))
    monkeypatch.setattr(events.DeployClient, "my_releases", lambda self: [
        {"id": 316432, "status": "launching", "summary": "차단 스위치"}])
    items = events.fetch("deploy.my_release_status")
    assert items[0]["key"] == "316432:launching"
