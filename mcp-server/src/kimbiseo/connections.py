"""연결 대상 시스템 목록 (shared/connections.json)."""

import json
import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class SystemDef:
    id: str
    name: str
    group: str
    enabled: bool
    base_url: str | None
    auth: str = "password"   # password: 사내 아이디·비밀번호 / gh: GitHub CLI 로그인
    web_url: str | None = None  # 사람이 여는 화면 주소 (API 주소와 다를 때)


def shared_dir() -> Path:
    override = os.environ.get("KIMBISEO_SHARED_DIR")
    if override:
        return Path(override)
    # mcp-server/src/kimbiseo/connections.py → 저장소 루트/shared
    return Path(__file__).resolve().parents[3] / "shared"


def connections_file() -> Path:
    """회사 주소가 든 connections.local.json(저장소에 올리지 않음)이 있으면 그것을, 없으면 예시 파일을 쓴다."""
    local = shared_dir() / "connections.local.json"
    return local if local.exists() else shared_dir() / "connections.example.json"


def load_systems(path: Path | None = None) -> list[SystemDef]:
    raw = json.loads((path or connections_file()).read_text(encoding="utf-8"))
    return [
        SystemDef(id=s["id"], name=s["name"], group=s["group"], enabled=bool(s["enabled"]), base_url=s.get("baseUrl"),
                  auth=s.get("auth", "password"), web_url=s.get("webUrl"))
        for s in raw
    ]


def find_system(system_id: str, systems: list[SystemDef] | None = None) -> SystemDef | None:
    return next((s for s in (systems or load_systems()) if s.id == system_id), None)
