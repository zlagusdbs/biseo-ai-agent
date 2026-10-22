"""사내 Deploy (배포 관리) REST API 조회. 사내 계정 Basic 인증."""

from .basic_client import BasicClient

SYSTEM = "deploy"


def _release(x: dict) -> dict:
    def name(v):
        return v.get("name") if isinstance(v, dict) else v
    return {
        "id": x.get("id"),
        "domainId": x.get("domainId"),
        "summary": x.get("summary") or "",
        "description": (x.get("description") or "")[:200],
        "status": x.get("status"),
        "creatingUser": name(x.get("creatingUser")),
        "approver": name(x.get("approver")),
        "created": (x.get("created") or "")[:16],
    }


class DeployClient(BasicClient):
    system = SYSTEM

    def verify(self) -> None:
        self._get("/api/releases")

    def my_releases(self) -> list[dict]:
        return [_release(x) for x in self._get("/api/releases").json() or []]

    def approvals(self) -> list[dict]:
        return [_release(x) for x in self._get("/api/releases/approvals").json() or []]

    def domain_releases(self, domain: str, status: str = "", limit: int = 20) -> list[dict]:
        data = self._get(f"/api/domains/{domain}/releases", params={"status": status, "offset": 0, "limit": limit}).json()
        return [_release(x) for x in data or []]

    def search(self, start_date: str, end_date: str) -> list[dict]:
        data = self._get("/api/releases/search", params={"startDate": start_date, "endDate": end_date}).json()
        return [_release(x) for x in data or []]
