from kimbiseo import rules


def test_read_skill(tmp_path, monkeypatch):
    monkeypatch.setenv("KIMBISEO_DATA_DIR", str(tmp_path))
    (tmp_path / "skills").mkdir()
    (tmp_path / "skills" / "jira.md").write_text("# Jira\n- 프로젝트 키: X", encoding="utf-8")
    assert rules.read("jira")["text"].startswith("# Jira")
    assert rules.read("skills/jira.md")["name"] == "skills/jira.md"
    missing = rules.read("../settings")
    assert missing["error"] == "NOT_FOUND" and missing["available"] == ["jira.md"]
