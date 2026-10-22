"""사내 Permit. HR 와 같은 ASP.NET 폼 로그인(/Account/Authenticate, AD 계정)이라 로그인은 HrClient 를 그대로 쓴다.

지금은 연결 확인(로그인)만 한다.
"""

from .hr_client import HrClient


class PermitClient(HrClient):
    system = "permit"
    home = "/Permit/Home"
