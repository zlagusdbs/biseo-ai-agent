"""트리거 알림용 이벤트 조회. 각 이벤트는 '지금 상태'의 항목 목록을 돌려주고,
앱은 이전 목록과 비교해 새로 생긴 key 만 알린다 (상태가 바뀌면 key 가 바뀌도록 만든다)."""

from collections.abc import Callable
from dataclasses import asdict, dataclass

from . import credentials, github_client
from .connections import SystemDef, find_system
from .credentials import Credential
from .errors import NotConnected
from .jira_client import JiraClient
from .deploy_client import DeployClient


@dataclass(frozen=True)
class EventItem:
    key: str        # 새로 생겼는지 비교하는 값
    title: str
    summary: str
    url: str


@dataclass(frozen=True)
class EventDef:
    id: str
    system: str
    name: str


EVENTS = [
    EventDef("github.review_requested", "github", "리뷰어로 지정됐을 때"),
    EventDef("github.my_pr_approved", "github", "내 PR 이 승인됐을 때"),
    EventDef("github.my_pr_feedback", "github", "내 PR 에 변경 요청이나 댓글이 달렸을 때"),
    EventDef("deploy.approval_requested", "deploy", "내가 승인해야 할 배포가 생겼을 때"),
    EventDef("deploy.my_release_status", "deploy", "내 배포 상태가 바뀌었을 때"),
    EventDef("jira.assigned_to_me", "jira", "나에게 새 이슈가 할당됐을 때"),
    EventDef("jira.my_issue_status", "jira", "내 이슈 상태가 바뀌었을 때"),
]

MY_OPEN_JQL = "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC"


def _system(system_id: str) -> tuple[SystemDef, Credential]:
    system = find_system(system_id)
    if system is None or not system.enabled or not system.base_url:
        raise NotConnected(system_id)
    if system.auth == "gh":
        if not github_client.is_logged_in(system.base_url):
            raise NotConnected(system_id)
        return system, Credential("", "")
    cred = credentials.load(system_id)
    if cred is None:
        raise NotConnected(system_id)
    return system, cred


# --- GitHub -----------------------------------------------------------------

def _github_review_requested() -> list[EventItem]:
    system, _ = _system("github")
    return [EventItem(str(pr["id"]), f"리뷰 요청 · {pr['repo'].split('/')[-1]} #{pr['number']}",
                      f"{pr['title']} · {pr['author']}", pr["url"])
            for pr in github_client.review_requests(system.base_url)]


def _github_my_reviews(want: set[str]) -> list[EventItem]:
    system, _ = _system("github")
    me = github_client.me(system.base_url)
    items = []
    for pr in github_client.my_open_prs(system.base_url):
        repo_name = pr["repo"].split("/")[-1]
        for review in github_client.reviews(system.base_url, pr["repo"], pr["number"]):
            reviewer = (review.get("user") or {}).get("login", "")
            if reviewer == me or review.get("state") not in want:
                continue
            label = {"APPROVED": "승인", "CHANGES_REQUESTED": "변경 요청", "COMMENTED": "리뷰 댓글"}[review["state"]]
            items.append(EventItem(f"review:{review['id']}", f"{label} · {repo_name} #{pr['number']}",
                                   f"{pr['title']} · {reviewer}", review.get("html_url") or pr["url"]))
        if "COMMENTED" in want:
            for comment in github_client.issue_comments(system.base_url, pr["repo"], pr["number"]):
                author = (comment.get("user") or {}).get("login", "")
                if author == me:
                    continue
                body = " ".join((comment.get("body") or "").split())[:80]
                items.append(EventItem(f"comment:{comment['id']}", f"댓글 · {repo_name} #{pr['number']}",
                                       f"{author}: {body}", comment.get("html_url") or pr["url"]))
    return items


# --- Deploy --------------------------------------------------------------------

def _deploy_web(system: SystemDef) -> str:
    return (system.web_url or system.base_url or "").rstrip("/")


def _deploy_approval_requested() -> list[EventItem]:
    system, cred = _system("deploy")
    return [EventItem(str(r["id"]), f"배포 승인 요청 · {r['id']}", f"{r['summary']} · {r['creatingUser']}", _deploy_web(system))
            for r in DeployClient(system.base_url, cred).approvals()]


def _deploy_my_release_status() -> list[EventItem]:
    system, cred = _system("deploy")
    return [EventItem(f"{r['id']}:{r['status']}", f"내 배포 {r['id']} · {r['status']}", r["summary"], _deploy_web(system))
            for r in DeployClient(system.base_url, cred).my_releases()]


# --- Jira -------------------------------------------------------------------

def _jira_items(with_status: bool) -> list[EventItem]:
    system, cred = _system("jira")
    result = JiraClient(system.base_url, cred).search(MY_OPEN_JQL, 50)
    return [EventItem(f"{i.key}:{i.status}" if with_status else i.key,
                      f"{'이슈 상태 ' + i.status if with_status else '새 이슈 할당'} · {i.key}", i.summary, i.url)
            for i in result.issues]


HANDLERS: dict[str, Callable[[], list[EventItem]]] = {
    "github.review_requested": _github_review_requested,
    "github.my_pr_approved": lambda: _github_my_reviews({"APPROVED"}),
    "github.my_pr_feedback": lambda: _github_my_reviews({"CHANGES_REQUESTED", "COMMENTED"}),
    "deploy.approval_requested": _deploy_approval_requested,
    "deploy.my_release_status": _deploy_my_release_status,
    "jira.assigned_to_me": lambda: _jira_items(with_status=False),
    "jira.my_issue_status": lambda: _jira_items(with_status=True),
}


def fetch(event_id: str) -> list[dict]:
    if event_id not in HANDLERS:
        raise KeyError(event_id)
    return [asdict(item) for item in HANDLERS[event_id]()]
