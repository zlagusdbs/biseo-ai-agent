"""사내 시스템 호출 오류. code 는 도구 결과와 앱이 그대로 읽는 문자열이다."""


class KimbiseoError(Exception):
    prefix = "ERROR"

    def __init__(self, system: str, detail: str = ""):
        super().__init__(f"{self.prefix}:{system} {detail}".strip())
        self.system = system

    @property
    def code(self) -> str:
        return f"{self.prefix}:{self.system}"


class AuthExpired(KimbiseoError):
    prefix = "AUTH_EXPIRED"


class NetworkUnreachable(KimbiseoError):
    prefix = "NETWORK_UNREACHABLE"


class NotConnected(KimbiseoError):
    prefix = "NOT_CONNECTED"
