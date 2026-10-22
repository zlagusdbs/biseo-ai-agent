"""사내 GitHub Enterprise 조회. 이미 로그인된 GitHub CLI(gh)의 인증을 그대로 쓴다 (토큰을 따로 저장하지 않는다)."""

import json
import shutil
import subprocess
from urllib.parse import urlparse

from .errors import AuthExpired, KimbiseoError, NetworkUnreachable

SYSTEM = "github"
REVIEW_QUERY = "is:pr is:open review-requested:@me archived:false"


def host_of(base_url: str) -> str:
    return urlparse(base_url).hostname or base_url


def gh_path() -> str:
    path = shutil.which("gh") or "/opt/homebrew/bin/gh"
    if not shutil.which(path):
        raise KimbiseoError(SYSTEM, "GitHub CLI(gh)가 설치돼 있지 않아요")
    return path


def is_logged_in(base_url: str) -> bool:
    try:
        result = subprocess.run([gh_path(), "auth", "status", "--hostname", host_of(base_url)],
                                capture_output=True, text=True, timeout=20)
    except (KimbiseoError, subprocess.TimeoutExpired):
        return False
    return result.returncode == 0


def _api(base_url: str, args: list[str]):
    try:
        result = subprocess.run([gh_path(), "api", "--hostname", host_of(base_url), *args],
                                capture_output=True, text=True, timeout=30)
    except subprocess.TimeoutExpired as e:
        raise NetworkUnreachable(SYSTEM, "응답 없음") from e
    if result.returncode != 0:
        err = (result.stderr or result.stdout).lower()
        if "401" in err or "auth" in err or "login" in err:
            raise AuthExpired(SYSTEM, result.stderr.strip())
        if "connect" in err or "timeout" in err or "resolve" in err:
            raise NetworkUnreachable(SYSTEM, result.stderr.strip())
        raise KimbiseoError(SYSTEM, result.stderr.strip()[:200])
    return json.loads(result.stdout or "{}")


def pull_request_rows(search_result: dict) -> list[dict]:
    rows = []
    for item in search_result.get("items", []):
        repo = "/".join((item.get("repository_url") or "").split("/")[-2:])
        rows.append({
            "id": item.get("id"),
            "repo": repo,
            "number": item.get("number"),
            "title": item.get("title", ""),
            "author": (item.get("user") or {}).get("login", ""),
            "url": item.get("html_url", ""),
            "updated": (item.get("updated_at") or "")[:16],
        })
    return rows


def review_requests(base_url: str, limit: int = 50) -> list[dict]:
    """내가 리뷰어로 지정된 열린 PR."""
    data = _api(base_url, ["-X", "GET", "search/issues", "-f", f"q={REVIEW_QUERY}", "-f", f"per_page={limit}",
                           "-f", "sort=updated"])
    return pull_request_rows(data)


def me(base_url: str) -> str:
    return _api(base_url, ["user"]).get("login", "")


def my_open_prs(base_url: str, limit: int = 30) -> list[dict]:
    data = _api(base_url, ["-X", "GET", "search/issues", "-f", "q=is:pr is:open author:@me archived:false",
                           "-f", f"per_page={limit}", "-f", "sort=updated"])
    return pull_request_rows(data)


def reviews(base_url: str, repo: str, number: int) -> list[dict]:
    data = _api(base_url, [f"repos/{repo}/pulls/{number}/reviews"])
    return data if isinstance(data, list) else []


def issue_comments(base_url: str, repo: str, number: int) -> list[dict]:
    data = _api(base_url, [f"repos/{repo}/issues/{number}/comments"])
    return data if isinstance(data, list) else []
