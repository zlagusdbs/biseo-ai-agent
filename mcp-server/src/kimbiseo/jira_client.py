"""사내 Jira REST API (조회 전용)."""

from dataclasses import dataclass

from .basic_client import BasicClient

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
