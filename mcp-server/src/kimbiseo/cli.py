"""kimbiseo 명령어. 앱이 연결 관리할 때 직접 실행하고, serve 는 MCP 서버를 띄운다.

  kimbiseo connect <시스템>         표준 입력: 첫 줄 아이디, 나머지 전체 비밀번호
  kimbiseo connect --group <그룹>   같은 계정으로 그룹 전체 연결
  kimbiseo status                  시스템별 연결 상태
  kimbiseo github review-requests  내가 리뷰어인 열린 PR (GitHub CLI 로그인 사용)
  kimbiseo jira worklog            작업 시간 기록. 표준 입력: {"issueKey","started","timeSpentSeconds","comment"} (앱 확인 카드에서만 부름)
  kimbiseo jira create             이슈 등록. 표준 입력: {"project","issueType","summary","description",
                                   "originalEstimate","targetStart","targetEnd","epicLink"} (앱 확인 카드에서만 부름)
  kimbiseo serve                   MCP 서버 (stdio)
"""

import argparse
import json
import sys
from collections.abc import Callable
from typing import TextIO

from . import credentials
from .connections import SystemDef, load_systems
from .credentials import Credential
from .errors import AuthExpired, KimbiseoError, NetworkUnreachable
from .approval_client import ApprovalClient
from .hr_client import HrClient
from .permit_client import PermitClient
from . import github_client
from .connections import find_system
from .jira_client import IssueDraft, JiraClient
from .deploy_client import DeployClient
from .wiki_client import WikiClient

Verifier = Callable[[SystemDef, Credential], None]


VERIFIERS: dict[str, Verifier] = {
    "jira": lambda system, cred: JiraClient(system.base_url or "", cred).verify(),
    "wiki": lambda system, cred: WikiClient(system.base_url or "", cred).verify(),
    "hr": lambda system, cred: HrClient(system.base_url or "", cred).verify(),
    "deploy": lambda system, cred: DeployClient(system.base_url or "", cred).verify(),
    "approval": lambda system, cred: ApprovalClient(system.base_url or "", cred, system.login_domain or "").verify(),
    "permit": lambda system, cred: PermitClient(system.base_url or "", cred).verify(),
}

MESSAGES = {
    "connected": "연결됐어요",
    "auth_failed": "아이디 또는 비밀번호를 확인해 주세요",
    "network_unreachable": "사내망 연결을 확인해 주세요",
    "unavailable": "아직 준비 중이에요",
}


def read_credential(stdin: TextIO) -> Credential | None:
    text = stdin.read()
    if text.endswith("\n"):
        text = text[:-1]
    username, sep, secret = text.partition("\n")
    username = username.strip()
    if not sep or not username or not secret:
        return None
    return Credential(username, secret)


def connect_one(system: SystemDef, cred: Credential, verifiers: dict[str, Verifier]) -> dict:
    if system.auth == "gh":
        return {"system": system.id, "status": "unavailable", "message": "GitHub 은 연결 화면의 [연결] 로 따로 로그인해요"}
    if system.auth == "claude.ai":
        return {"system": system.id, "status": "unavailable", "message": "claude.ai 설정에서 연결해요"}
    verifier = verifiers.get(system.id)
    if not system.enabled or verifier is None:
        status = "unavailable"
    else:
        try:
            verifier(system, cred)
            credentials.save(system.id, cred)
            status = "connected"
        except AuthExpired:
            status = "auth_failed"
        except NetworkUnreachable:
            status = "network_unreachable"
        except KimbiseoError as e:
            return {"system": system.id, "status": "error", "message": f"연결하지 못했어요: {e}"}
    return {"system": system.id, "status": status, "message": MESSAGES[status]}


def system_status(system: SystemDef, verifiers: dict[str, Verifier]) -> str:
    if system.auth == "claude.ai":
        return "external"   # claude.ai 커넥터는 앱이 claude mcp list 로 확인한다
    if system.enabled and system.auth == "gh":
        return "connected" if github_client.is_logged_in(system.base_url or "") else "disconnected"
    if not system.enabled or system.id not in verifiers:
        return "unavailable"
    if credentials.load(system.id) is None:
        return "disconnected"
    return "expired" if credentials.is_expired(system.id) else "connected"


def _jira_or_fail(systems: list[SystemDef]) -> JiraClient | None:
    system = find_system("jira", systems)
    cred = credentials.load("jira")
    if system is None or not system.enabled or not system.base_url or cred is None:
        return None
    return JiraClient(system.base_url, cred)


def jira_worklog(stdin: TextIO, stdout: TextIO, systems: list[SystemDef]) -> int:
    def fail(code: str, detail: str = "") -> int:
        print(json.dumps({"error": code, "detail": detail}, ensure_ascii=False), file=stdout)
        return 1

    try:
        data = json.loads(stdin.read())
        key, started, seconds = str(data["issueKey"]).strip(), str(data["started"]).strip(), int(data["timeSpentSeconds"])
    except (ValueError, KeyError, TypeError, AttributeError) as e:
        return fail("BAD_INPUT", str(e))
    client = _jira_or_fail(systems)
    if client is None:
        return fail("NOT_CONNECTED:jira")
    try:
        result = client.add_worklog(key, started, seconds, str(data.get("comment") or ""))
    except AuthExpired as e:
        credentials.mark_expired("jira")
        return fail(e.code)
    except KimbiseoError as e:
        return fail(e.code, str(e).removeprefix(e.code).strip())
    print(json.dumps(result, ensure_ascii=False), file=stdout)
    return 0


def jira_create(stdin: TextIO, stdout: TextIO, systems: list[SystemDef]) -> int:
    def fail(code: str, detail: str = "") -> int:
        print(json.dumps({"error": code, "detail": detail}, ensure_ascii=False), file=stdout)
        return 1

    try:
        draft = IssueDraft.from_json(json.loads(stdin.read()))
    except (ValueError, AttributeError) as e:
        return fail("BAD_INPUT", str(e))
    if not (draft.project and draft.issue_type and draft.summary):
        return fail("BAD_INPUT", "프로젝트, 이슈 유형, 제목은 꼭 있어야 해요")
    system = find_system("jira", systems)
    cred = credentials.load("jira")
    if system is None or not system.enabled or not system.base_url or cred is None:
        return fail("NOT_CONNECTED:jira")
    try:
        issue = JiraClient(system.base_url, cred).create_issue(draft)
    except AuthExpired as e:
        credentials.mark_expired("jira")
        return fail(e.code)
    except KimbiseoError as e:
        return fail(e.code, str(e).removeprefix(e.code).strip())
    print(json.dumps({"key": issue.key, "url": issue.url}, ensure_ascii=False), file=stdout)
    return 0


def main(argv: list[str] | None = None, stdin: TextIO = sys.stdin, stdout: TextIO = sys.stdout,
         verifiers: dict[str, Verifier] | None = None) -> int:
    verifiers = VERIFIERS if verifiers is None else verifiers
    parser = argparse.ArgumentParser(prog="kimbiseo")
    sub = parser.add_subparsers(dest="command", required=True)
    connect = sub.add_parser("connect")
    connect.add_argument("system", nargs="?")
    connect.add_argument("--group")
    sub.add_parser("status")
    events = sub.add_parser("events")
    events.add_argument("event", help="이벤트 id. --list 로 목록")
    github = sub.add_parser("github")
    github.add_argument("action", choices=["review-requests"])
    jira = sub.add_parser("jira")
    jira.add_argument("action", choices=["create", "worklog"])
    sub.add_parser("serve")
    args = parser.parse_args(argv)

    systems = load_systems()

    if args.command == "serve":
        from .server import run
        run()
        return 0

    if args.command == "events":
        from . import events as event_module
        if args.event == "--list" or args.event == "list":
            print(json.dumps([{"id": e.id, "system": e.system, "name": e.name} for e in event_module.EVENTS],
                             ensure_ascii=False), file=stdout)
            return 0
        try:
            rows = event_module.fetch(args.event)
        except KeyError:
            print(json.dumps({"error": f"알 수 없는 이벤트: {args.event}"}, ensure_ascii=False), file=stdout)
            return 2
        except KimbiseoError as e:
            print(json.dumps({"error": e.code, "detail": str(e)}, ensure_ascii=False), file=stdout)
            return 1
        print(json.dumps(rows, ensure_ascii=False), file=stdout)
        return 0

    if args.command == "github":
        system = find_system("github", systems)
        if system is None or not system.enabled or not system.base_url:
            print(json.dumps({"error": "NOT_CONNECTED:github"}), file=stdout)
            return 1
        try:
            rows = github_client.review_requests(system.base_url)
        except KimbiseoError as e:
            print(json.dumps({"error": e.code, "detail": str(e)}, ensure_ascii=False), file=stdout)
            return 1
        print(json.dumps(rows, ensure_ascii=False), file=stdout)
        return 0

    if args.command == "jira":
        if args.action == "worklog":
            return jira_worklog(stdin, stdout, systems)
        return jira_create(stdin, stdout, systems)

    if args.command == "status":
        out = [{"system": s.id, "name": s.name, "group": s.group, "auth": s.auth, "baseUrl": s.base_url,
                "company": s.company, "status": system_status(s, verifiers)} for s in systems]
        print(json.dumps(out, ensure_ascii=False), file=stdout)
        return 0

    if bool(args.system) == bool(args.group):
        print(json.dumps({"error": "시스템 이름 또는 --group 중 하나만 지정해 주세요"}, ensure_ascii=False), file=stdout)
        return 2
    targets = [s for s in systems if (s.id == args.system if args.system else s.group == args.group)]
    cred = read_credential(stdin)
    if not targets or cred is None:
        print(json.dumps({"error": "대상 시스템이 없거나 입력 형식이 잘못됐어요"}, ensure_ascii=False), file=stdout)
        return 2
    results = [connect_one(s, cred, verifiers) for s in targets]
    print(json.dumps(results, ensure_ascii=False), file=stdout)
    ok = all(r["status"] in ("connected", "unavailable") for r in results)
    return 0 if ok else 1
