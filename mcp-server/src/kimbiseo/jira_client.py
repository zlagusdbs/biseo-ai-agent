"""사내 Jira REST API. 조회와, 사용자가 확인 카드에서 누른 이슈 등록(create_issue)만 한다."""

from dataclasses import dataclass

from .basic_client import BasicClient
from .errors import RequestRejected

SYSTEM = "jira"
INCOMPLETE_JQL = "assignee = currentUser() AND statusCategory != Done ORDER BY duedate ASC, priority DESC"


@dataclass(frozen=True)
class Issue:
    key: str
    summary: str
    status: str
    priority: str | None
    due: str | None
    url: str


@dataclass(frozen=True)
class IssueDraft:
    """등록할 이슈. 날짜는 yyyy-MM-dd, 추정은 Jira 형식(365d, 2w, 4h)."""
    project: str
    issue_type: str
    summary: str
    description: str
    original_estimate: str = ""
    target_start: str = ""
    target_end: str = ""
    epic_link: str = ""

    @classmethod
    def from_json(cls, data: dict) -> "IssueDraft":
        return cls(
            project=str(data.get("project", "")).strip(),
            issue_type=str(data.get("issueType", "")).strip(),
            summary=str(data.get("summary", "")).strip(),
            description=str(data.get("description", "")),
            original_estimate=str(data.get("originalEstimate") or "").strip(),
            target_start=str(data.get("targetStart") or "").strip(),
            target_end=str(data.get("targetEnd") or "").strip(),
            epic_link=str(data.get("epicLink") or "").strip(),
        )


# 회사마다 사용자 정의 필드 ID 가 달라서 이름으로 찾는다.
TARGET_START = "Target start"
TARGET_END = "Target end"
EPIC_LINK = "Epic Link"


@dataclass(frozen=True)
class SearchResult:
    issues: list[Issue]
    total: int
    truncated: bool


class JiraClient(BasicClient):
    system = SYSTEM

    def verify(self) -> None:
        """로그인 확인. 실패하면 AuthExpired / NetworkUnreachable."""
        self._get("/rest/api/2/myself")

    def search(self, jql: str, max_results: int = 50) -> SearchResult:
        data = self._get(
            "/rest/api/2/search",
            params={"jql": jql, "maxResults": max_results, "fields": "summary,status,priority,duedate"},
        ).json()
        issues = [self._issue(raw) for raw in data.get("issues", [])]
        total = int(data.get("total", len(issues)))
        return SearchResult(issues=issues, total=total, truncated=total > len(issues))

    def myself(self) -> str:
        """로그인한 사용자 이름 (담당자·보고자로 쓴다)."""
        return self._get("/rest/api/2/myself").json()["name"]

    def projects(self, query: str = "") -> list[dict]:
        """프로젝트 키·이름. query 가 있으면 키나 이름에 들어간 것만."""
        q = query.strip().lower()
        rows = [{"key": p["key"], "name": p["name"]} for p in self._get("/rest/api/2/project").json()]
        return [r for r in rows if not q or q in r["key"].lower() or q in r["name"].lower()]

    def create_fields(self, project: str, issue_type: str) -> tuple[str, dict[str, str]]:
        """이슈 유형 ID 와 {필드 이름: 필드 ID}. 유형 이름은 대소문자를 가리지 않는다."""
        types = self._get(f"/rest/api/2/issue/createmeta/{project}/issuetypes").json()
        types = types.get("values", types) if isinstance(types, dict) else types
        found = next((t for t in types if t["name"].lower() == issue_type.lower()), None)
        if found is None:
            names = ", ".join(t["name"] for t in types)
            raise RequestRejected(self.system, f"{project} 프로젝트에 '{issue_type}' 유형이 없어요 (있는 유형: {names})")
        meta = self._get(f"/rest/api/2/issue/createmeta/{project}/issuetypes/{found['id']}").json()
        fields = {f["name"].strip(): f["fieldId"] for f in meta.get("values", [])}
        return found["id"], fields

    def create_issue(self, draft: IssueDraft) -> Issue:
        """이슈 등록. 담당자·보고자는 로그인한 본인. 프로젝트에 없는 선택 필드는 빼고 보낸다."""
        type_id, fields = self.create_fields(draft.project, draft.issue_type)
        me = self.myself()
        body: dict = {
            "project": {"key": draft.project},
            "issuetype": {"id": type_id},
            "summary": draft.summary,
            "description": draft.description,
            "assignee": {"name": me},
        }
        if "Reporter" in fields:
            body["reporter"] = {"name": me}
        if draft.original_estimate and "Time Tracking" in fields:
            body["timetracking"] = {"originalEstimate": draft.original_estimate}
        for name, value in ((TARGET_START, draft.target_start), (TARGET_END, draft.target_end),
                            (EPIC_LINK, draft.epic_link)):
            if value and name in fields:
                body[fields[name]] = value
        key = self._post("/rest/api/2/issue", {"fields": body}).json()["key"]
        return Issue(key=key, summary=draft.summary, status="", priority=None, due=None,
                     url=f"{self.base_url}/browse/{key}")

    def _issue(self, raw: dict) -> Issue:
        fields = raw.get("fields", {})
        return Issue(
            key=raw["key"],
            summary=fields.get("summary", ""),
            status=(fields.get("status") or {}).get("name", ""),
            priority=(fields.get("priority") or {}).get("name"),
            due=fields.get("duedate"),
            url=f"{self.base_url}/browse/{raw['key']}",
        )
