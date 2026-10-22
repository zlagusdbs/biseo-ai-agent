from kimbiseo.credentials import Credential, is_expired, load, mark_expired, save
from kimbiseo.errors import AuthExpired, NetworkUnreachable, NotConnected


def test_codes():
    assert AuthExpired("jira").code == "AUTH_EXPIRED:jira"
    assert NetworkUnreachable("jira").code == "NETWORK_UNREACHABLE:jira"
    assert NotConnected("jira").code == "NOT_CONNECTED:jira"


def test_save_load_roundtrip():
    save("jira", Credential("user", "p w 한글!"))
    assert load("jira") == Credential("user", "p w 한글!")


def test_load_missing_returns_none():
    assert load("hr") is None


def test_expired_flag_cleared_on_save():
    save("jira", Credential("user", "pw1"))
    mark_expired("jira")
    assert is_expired("jira")
    save("jira", Credential("user", "pw2"))
    assert not is_expired("jira")
