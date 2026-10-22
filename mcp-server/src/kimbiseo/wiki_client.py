"""사내 Wiki (Confluence DC) REST API (조회 전용). 사내 계정 Basic 인증."""

import html
import re
from dataclasses import dataclass

from .basic_client import BasicClient

SYSTEM = "wiki"
PAGE_TEXT_LIMIT = 8000


@dataclass(frozen=True)
class WikiPage:
    id: str
    title: str
    space: str
    url: str
    excerpt: str = ""


def cql_for(query: str) -> str:
    """검색어 → CQL. 따옴표·역슬래시는 이스케이프한다."""
    escaped = query.replace("\\", "\\\\").replace('"', '\\"')
    return f'siteSearch ~ "{escaped}" AND type = page'


def html_to_text(body: str) -> str:
    text = re.sub(r"<(br|/p|/li|/h[1-6]|/tr)[^>]*>", "\n", body, flags=re.I)
    text = re.sub(r"<[^>]+>", "", text)
    text = html.unescape(text)
    return re.sub(r"\n{3,}", "\n\n", text).strip()


class WikiClient(BasicClient):
    system = SYSTEM

    def verify(self) -> None:
        self._get("/rest/api/user/current")

    def search(self, query: str, limit: int = 10) -> list[WikiPage]:
        data = self._get("/rest/api/search", params={"cql": cql_for(query), "limit": limit}).json()
        pages = []
        for row in data.get("results", []):
            content = row.get("content") or {}
            if not content.get("id"):
                continue
            pages.append(WikiPage(
                id=str(content["id"]),
                title=content.get("title") or row.get("title", ""),
                space=(row.get("resultGlobalContainer") or {}).get("title", ""),
                url=self.base_url + (row.get("url") or (content.get("_links") or {}).get("webui", "")),
                excerpt=html_to_text(row.get("excerpt", ""))[:300],
            ))
        return pages

    def get_page(self, page_id: str) -> dict:
        data = self._get(f"/rest/api/content/{page_id}", params={"expand": "body.storage,space,version"}).json()
        text = html_to_text(((data.get("body") or {}).get("storage") or {}).get("value", ""))
        return {
            "id": str(data.get("id", page_id)),
            "title": data.get("title", ""),
            "space": (data.get("space") or {}).get("name", ""),
            "url": self.base_url + ((data.get("_links") or {}).get("webui", "")),
            "text": text[:PAGE_TEXT_LIMIT],
            "truncated": len(text) > PAGE_TEXT_LIMIT,
        }
