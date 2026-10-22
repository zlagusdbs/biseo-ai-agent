"""김비서 폴더(앱 데이터 폴더)의 skills/*.md 읽기. 앱의 Rules.swift 와 같은 폴더를 본다."""

from pathlib import Path

from . import credentials


def skills_dir() -> Path:
    return credentials.data_dir() / "skills"


def read(name: str) -> dict:
    stem = Path(name.strip()).name.removesuffix(".md")
    path = skills_dir() / f"{stem}.md"
    if not stem or path.parent != skills_dir() or not path.is_file():
        names = sorted(p.name for p in skills_dir().glob("*.md")) if skills_dir().is_dir() else []
        return {"error": "NOT_FOUND", "detail": f"skills/{stem}.md 가 없어요", "available": names}
    return {"name": f"skills/{path.name}", "text": path.read_text(encoding="utf-8")}
