"""김비서 MCP 서버. Claude Code 가 stdio 로 띄워 도구를 호출한다. 모든 도구는 조회 전용이다.
(이슈 등록은 도구로 열지 않고, 사용자가 앱의 확인 카드에서 누를 때 `kimbiseo jira create` 로만 한다.)"""

import datetime
from collections.abc import Callable
from typing import Any

from mcp.server.mcpserver import MCPServer

from . import credentials
from .connections import find_system
from .credentials import Credential
from .hr_client import HrClient
from .errors import AuthExpired, KimbiseoError, NetworkUnreachable, NotConnected
from . import github_client
from .jira_client import INCOMPLETE_JQL, JiraClient
from .deploy_client import DeployClient
from .wiki_client import WikiClient

mcp = MCPServer(
    name="kimbiseo",
    instructions="사내 시스템(Jira, Wiki, HR) 조회 도구. 조회 전용이다. 결과에 error 가 있으면 그 코드를 사용자에게 그대로 알린다.",
)


def _with_system(system_id: str, work: Callable[[str, Credential], Any]) -> Any:
    """연결 확인 → 작업 실행. 오류는 {"error": 코드} 로 돌려주고, 로그인 실패면 만료로 표시한다."""
    try:
        system = find_system(system_id)
        cred = credentials.load(system_id) if system is None or system.auth != "gh" else Credential("", "")
        if cred is None or system is None or not system.base_url or not system.enabled:
            raise NotConnected(system_id)
        return work(system.base_url, cred)
    except AuthExpired as e:
        credentials.mark_expired(system_id)
        return {"error": e.code}
    except (NotConnected, NetworkUnreachable) as e:
        return {"error": e.code}
    except KimbiseoError as e:
        return {"error": e.code, "detail": str(e)}


def jira_search(jql: str, max_results: int = 50) -> dict:
    """사내 Jira 이슈를 JQL 로 검색한다.

    내 미완료 이슈 JQL 예: assignee = currentUser() AND statusCategory != Done ORDER BY duedate ASC, priority DESC
    truncated 가 true 면 total 중 일부만 받은 것이다.
    """
    def work(base_url: str, cred: Credential) -> dict:
        r = JiraClient(base_url, cred).search(jql, max_results)
        return {
            "total": r.total,
            "truncated": r.truncated,
            "issues": [{"key": i.key, "summary": i.summary, "status": i.status, "priority": i.priority,
                        "due": i.due, "url": i.url} for i in r.issues],
        }
    return _with_system("jira", work)


def jira_projects(query: str = "") -> dict:
    """사내 Jira 프로젝트 키와 이름. 사용자가 말한 프로젝트 이름(예: Pricing)의 키를 찾을 때 쓴다."""
    return _with_system("jira", lambda base_url, cred: {"projects": JiraClient(base_url, cred).projects(query)})


def jira_my_worklogs(date: str = "") -> dict:
    """그날(yyyy-MM-dd, 비우면 오늘) 내가 Jira 에 남긴 작업 시간(worklog). 이슈별 시작 시각·시간(초)과 합계."""
    target = date or datetime.date.today().isoformat()
    return _with_system("jira", lambda base_url, cred: JiraClient(base_url, cred).my_worklogs(target))


def work_day_check(date: str = "") -> dict:
    """그날(yyyy-MM-dd, 비우면 오늘) HR 유연근무 시간과 내 Jira worklog 합계를 맞춰 본다.

    status: match(같음) | short(worklog 가 모자람, gapMinutes 만큼) | over(더 많음) | unknown(한쪽을 못 읽음).
    한쪽 시스템이 연결 안 됐으면 그쪽은 null 이고 errors 에 코드가 들어간다.
    """
    from .workday import compare
    target = date or datetime.date.today().isoformat()
    errors = []
    hr = _with_system("hr", lambda base_url, cred: HrClient(base_url, cred).flexwork_week(target))
    hr_day = None
    if "error" in hr:
        errors.append(hr["error"])
    else:
        hr_day = next((d for d in hr.get("days", []) if d.get("date") == target), None)
    logs = _with_system("jira", lambda base_url, cred: JiraClient(base_url, cred).my_worklogs(target))
    if "error" in logs:
        errors.append(logs["error"])
        logs = None
    result = compare(target, hr_day, logs)
    if errors:
        result["errors"] = errors
    return result


def read_skill(name: str) -> dict:
    """김비서 폴더 skills/ 의 스킬 md 를 읽는다. name 은 jira 또는 skills/jira.md 처럼.

    질문에 필요한 스킬 본문이 시스템 안내에 없을 때, 스킬 목록의 설명을 보고 필요한 것만 읽는다.
    """
    from . import rules
    return rules.read(name)


def wiki_search(query: str, limit: int = 10) -> dict:
    """사내 Wiki(Confluence) 페이지를 검색어로 찾는다. 결과의 id 로 wiki_get_page 를 호출하면 본문을 읽을 수 있다."""
    def work(base_url: str, cred: Credential) -> dict:
        pages = WikiClient(base_url, cred).search(query, limit)
        return {"pages": [{"id": p.id, "title": p.title, "space": p.space, "url": p.url, "excerpt": p.excerpt}
                          for p in pages]}
    return _with_system("wiki", work)


def wiki_get_page(page_id: str) -> dict:
    """사내 Wiki 페이지 본문을 텍스트로 읽는다 (최대 8000자, 넘으면 truncated=true)."""
    return _with_system("wiki", lambda base_url, cred: WikiClient(base_url, cred).get_page(page_id))


def hr_holidays() -> dict:
    """사내 휴무일·공휴일 목록 (HR)."""
    return _with_system("hr", lambda base_url, cred: {"holidays": HrClient(base_url, cred).holidays()})


def hr_flexwork_week(date: str = "") -> dict:
    """내 주간 근무일정 (HR 유연근무). date(yyyy-MM-dd)가 속한 2주를 돌려준다. 비우면 오늘."""
    target = date or datetime.date.today().isoformat()
    return _with_system("hr", lambda base_url, cred: HrClient(base_url, cred).flexwork_week(target))


def deploy_my_releases() -> dict:
    """내가 만든 Deploy 배포 목록 (상태·요약·생성일)."""
    return _with_system("deploy", lambda base_url, cred: {"releases": DeployClient(base_url, cred).my_releases()})


def deploy_approvals() -> dict:
    """내가 승인해야 할 Deploy 배포 목록."""
    return _with_system("deploy", lambda base_url, cred: {"releases": DeployClient(base_url, cred).approvals()})


def deploy_domain_releases(domain: str, status: str = "", limit: int = 20) -> dict:
    """Deploy 도메인(배포 대상, 예: pricing-front)의 최근 배포. status: Open|Approved|Launching|Closed (비우면 전체)."""
    return _with_system("deploy", lambda base_url, cred: {"releases": DeployClient(base_url, cred).domain_releases(domain, status, limit)})


def deploy_release_search(start_date: str, end_date: str) -> dict:
    """기간(yyyy-MM-dd ~ yyyy-MM-dd)의 전체 Deploy 배포 검색."""
    return _with_system("deploy", lambda base_url, cred: {"releases": DeployClient(base_url, cred).search(start_date, end_date)})


def github_review_requests() -> dict:
    """사내 GitHub 에서 내가 리뷰어로 지정된 열린 PR 목록 (저장소, 번호, 제목, 작성자, 링크)."""
    system = find_system("github")
    if system is None or not system.base_url or not github_client.is_logged_in(system.base_url):
        return {"error": "NOT_CONNECTED:github"}
    return _with_system("github", lambda base_url, cred: {"pullRequests": github_client.review_requests(base_url)})


TOOLS = [read_skill, jira_search, jira_projects, jira_my_worklogs, work_day_check, wiki_search, wiki_get_page, hr_holidays, hr_flexwork_week,
         deploy_my_releases, deploy_approvals, deploy_domain_releases, deploy_release_search, github_review_requests]
for _tool in TOOLS:
    mcp.tool()(_tool)

__all__ = ["mcp", "TOOLS", "INCOMPLETE_JQL", "run"] + [t.__name__ for t in TOOLS]


def run() -> None:
    mcp.run("stdio")
