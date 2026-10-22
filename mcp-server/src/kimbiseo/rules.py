"""김비서 폴더(앱 데이터 폴더)의 rules/*.md 읽기. 앱의 Rules.swift 와 같은 폴더를 본다."""

from pathlib import Path

from . import credentials


def rules_dir() -> Path:
    return credentials.data_dir() / "rules"


def read(name: str) -> dict:
    stem = Path(name.strip()).name.removesuffix(".md")
    path = rules_dir() / f"{stem}.md"
    if not stem or path.parent != rules_dir() or not path.is_file():
        names = sorted(p.name for p in rules_dir().glob("*.md")) if rules_dir().is_dir() else []
        return {"error": "NOT_FOUND", "detail": f"rules/{stem}.md 가 없어요", "available": names}
    return {"name": f"rules/{path.name}", "text": path.read_text(encoding="utf-8")}
