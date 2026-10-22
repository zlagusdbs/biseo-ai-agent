# 김비서 (biseo-ai-agent)

macOS 메뉴바에 사는 개인 업무 AI 비서. 단축키로 채팅창을 열고 대화하듯 요청하면, Claude 가 사내 시스템(사내 포털 Portal, Jira, Wiki, 인사·근태, 배포 관리 Deploy, 전자결재 Approval, Permit, GitHub Enterprise)과 Microsoft 365(메일·일정·Teams)를 **조회**해서 답한다. 정해 둔 시각에 알아서 보고하고, 내가 리뷰어로 지정된 PR 이 생기면 알려 준다.

- 대화형 채팅: 앞 대화를 이어서 질문, 이미지 첨부(📎 / ⌘V / 끌어다 놓기)
- 연결 관리: 사내 계정 한 번 입력으로 여러 시스템 일괄 연동 (비밀번호는 키체인에만 저장)
- 알림: "평일 09:00 미완료 Jira 정리"처럼 시각·반복·할 일을 등록 → Mac 알림 + 화면 오른쪽 아래 미리 알림 창(다시 알림, 확인)
- GitHub: 5분마다 내가 리뷰어인 열린 PR 을 확인해서 새 PR 을 알림 창으로 알려 줌 ([열기]로 바로 PR)
- 조회 전용: 메일 발송, 이슈 수정 같은 쓰기 작업은 하지 않는다

## 구조

```
김비서 앱 (Swift, 메뉴바)  ──claude -p──▶  Claude Code  ──▶  Anthropic (Claude)
                                             │
                                             ├─▶ 김비서 MCP 서버 (Python) ──▶ 사내 Jira / Wiki / HR / Deploy / GitHub(gh)
                                             └─▶ claude.ai Microsoft 365 커넥터 ──▶ 메일·일정·Teams
```

| 폴더 | 내용 |
|---|---|
| `app-mac/` | 메뉴바 앱 (SwiftUI + AppKit). 채팅, 연결, 알림, 설정, 전역 단축키 |
| `mcp-server/` | Python 패키지 `kimbiseo`. MCP 서버(`kimbiseo serve`)와 연결 관리 명령(`kimbiseo connect`, `kimbiseo status`) |
| `shared/` | 두 쪽이 같이 쓰는 설정: 연결 대상 목록, MCP 설정 템플릿, 프롬프트 |

엔진은 로그인된 Claude Code CLI 를 쓴다. 별도 API 키가 필요 없고, Claude Code 계정의 사용량으로 동작한다. `claude -p` 는 허용 도구 목록(김비서 MCP + Microsoft 365 조회 도구)만 쓰도록 제한해서 실행한다.

## 준비물

- macOS 15 이상, Xcode Command Line Tools (`xcode-select --install`)
- [Claude Code](https://code.claude.com) CLI — 처음 질문할 때 로그인이 필요하면 김비서가 브라우저를 띄운다
- [uv](https://docs.astral.sh/uv/) (`brew install uv`)
- (선택) [GitHub CLI](https://cli.github.com) `gh` — GitHub 리뷰 요청 알림용. 연결 화면에서 로그인할 수 있다
- (선택) claude.ai → 설정 → 커넥터에서 Microsoft 365 연결

## 설치

```bash
git clone https://github.com/zlagusdbs/biseo-ai-agent.git ~/Workspace/kim-biseo
cd ~/Workspace/kim-biseo

# 1. 회사 시스템 주소 설정 (이 파일은 Git 에 올라가지 않는다)
cp shared/connections.example.json shared/connections.local.json
#    → baseUrl 을 회사 Jira / Wiki / HR 주소로 바꾼다

# 2. MCP 서버 의존성 설치와 테스트
cd mcp-server && uv sync && uv run pytest && cd ..

# 3. 앱 빌드와 실행
./app-mac/scripts/bundle.sh
open app-mac/build/KimBiseo.app
```

### 규칙과 기억 (CLAUDE.md · rules · skills)

김비서 폴더(`~/Library/Application Support/kim-biseo/`)에서 Claude Code 처럼 md 로 관리한다. 처음 실행하면 `shared/templates/` 의 예시가 복사된다.

```
kim-biseo/
 ├ CLAUDE.md        root: 늘 적용하는 기본 지시. Claude Code 가 직접 읽음. 지울 수 없음
 ├ rules/           질문마다 모두 읽음. 짧게 (파일당 200줄 이하)
 │  └ memory.md     기억 (채팅에서 "기억해" → [기억하기])
 └ skills/          주제가 나올 때만 읽음
    └ jira.md       Jira 이슈 등록·worklog·우리 팀 기본값 (프로젝트 키, 기간, 고정 이슈 …)
```

- skills 는 맨 위 머리말로 설명과 키워드를 정한다. 질문마다 설명 한 줄만 보내고, 질문에 키워드가 있으면 본문을 붙인다. 키워드가 없어도 필요하면 김비서가 `read_skill` 로 읽는다.
  ```
  ---
  description: Jira 이슈 등록·worklog·기본값
  keywords: jira, 지라, 이슈, worklog, 회의
  ---
  ```
- ⚙️ 설정 → root / rules / skills 칸에서 파일을 열고, 지우고(CLAUDE.md 는 제외), 새로 만들 수 있다. 고친 내용은 다음 질문부터 바로 적용된다.
- 채팅에서 "앞으로 지라 제목 앞에 [회의] 붙여줘" 처럼 말하고 [규칙에 저장]을 누르면 같은 이름의 스킬(없으면 rules/)에 한 줄 추가된다.
- `skills/jira.md` 의 「우리 팀 기본값」 예:
  ```
  - 프로젝트 키: MYPROJ
  - 이슈 유형: 개발이면 Story, 일반 업무면 Task
  - Original Estimate 365d, Target start 는 등록하는 날, Target end 는 그해 12월 31일
  - worklog 를 남길 고정 이슈: 회의 → MYPROJ-100, 운영업무(CS) → MYPROJ-101
  ```

처음 실행하면 김비서가 주인 이름을 묻고 인사한다. 이름은 ⚙️ 설정에서 바꿀 수 있다.

저장소를 `~/Workspace/kim-biseo` 가 아닌 곳에 두었다면 앱의 ⚙️ 설정에서 저장소 경로를 바꾼다.

## 사용법

| 동작 | 방법 |
|---|---|
| 채팅창 열기·닫기 | 메뉴바 말풍선 아이콘 또는 단축키(기본 ⇧⌃⌥⌘ Space, ⚙️ 설정에서 변경), 닫기는 Esc |
| 사내 시스템 연결 | 오른쪽 🔌 → [일괄 연동] → 사내 아이디·비밀번호. GitHub 은 [연결] → 한 번용 코드로 브라우저 승인 |
| 알림 등록 | 오른쪽 🔔 → [추가] → 시각, 반복(매일/평일/요일/한 번), 시킬 내용 |
| 이름 바꾸기 | 채팅창 제목 옆 ✏️ |

질문 예: "내 미완료 Jira 알려줘", "내 리뷰 대기 PR", "내가 승인할 배포 있어?", "쿠폰 정책 위키 찾아줘", "이번 주 내 근무일정", "오늘 받은 메일 요약해줘", 스크린샷을 붙여넣고 "이 에러 뭐야?"

## 개발

```bash
cd mcp-server && uv run pytest                  # Python 테스트
cd app-mac && swift run KimBiseoCoreChecks      # Swift 로직 검증 (Xcode 없이 XCTest 를 못 써서 실행형으로 만듦)
cd mcp-server && uv run mcp dev src/kimbiseo/server.py   # MCP Inspector 로 도구 직접 호출
```

앱 데이터는 `~/Library/Application Support/kim-biseo/` (대화 기록, 알림, 첨부 이미지), 로그인 정보는 macOS 키체인(서비스 이름 `kim-biseo`)에 있다.

## 지원하지 않는 것

- 쓰기 작업 (메일 발송, Jira 수정, 휴가 신청 등)
- 인사 시스템의 휴가 잔여일 조회
- Windows (구조는 `shared/` 와 `mcp-server/` 를 그대로 쓰는 Java 앱을 염두에 두었지만 아직 없다)
