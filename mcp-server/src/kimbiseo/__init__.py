"""김비서 사내 시스템 연결 (MCP 서버 + 연결 관리 명령어)."""


def main() -> None:
    import sys

    from .cli import main as cli_main

    sys.exit(cli_main())
