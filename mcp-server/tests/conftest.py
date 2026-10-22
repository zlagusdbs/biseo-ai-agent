import keyring
import pytest
from keyring.backend import KeyringBackend


class MemoryKeyring(KeyringBackend):
    priority = 1

    def __init__(self):
        super().__init__()
        self.store: dict[tuple[str, str], str] = {}

    def set_password(self, service, username, password):
        self.store[(service, username)] = password

    def get_password(self, service, username):
        return self.store.get((service, username))

    def delete_password(self, service, username):
        if (service, username) not in self.store:
            raise keyring.errors.PasswordDeleteError(username)
        del self.store[(service, username)]


@pytest.fixture(autouse=True)
def isolated_storage(tmp_path, monkeypatch):
    """실제 키체인과 앱 폴더를 건드리지 않게 메모리 키체인과 임시 폴더로 바꾼다."""
    previous = keyring.get_keyring()
    keyring.set_keyring(MemoryKeyring())
    monkeypatch.setenv("KIMBISEO_DATA_DIR", str(tmp_path / "data"))
    yield
    keyring.set_keyring(previous)
