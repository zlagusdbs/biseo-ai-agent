import Foundation
import KimBiseoCore

// Xcode 없이 XCTest 를 쓸 수 없어서 만든 검증 프로그램. `swift run KimBiseoCoreChecks`
var failures = 0
var passed = 0

func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    if condition() { passed += 1 } else { failures += 1; print("FAIL: \(name)") }
}

// MARK: ClaudeCommand
do {
    let a = ClaudeCommand.arguments(sessionId: nil, mcpConfigPath: "/c.json", systemPrompt: "sys")
    check(a.first == "-p" && a.contains("stream-json") && !a.contains("질문"), "arguments: 질문은 인자가 아니라 표준 입력으로")
    let line = ClaudeCommand.inputLine(prompt: "질문", images: [ImageAttachment(mediaType: "image/png", data: Data([1, 2]), path: "/x")])
    let parsed = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
    let content = ((parsed?["message"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []
    check(content.count == 2 && content[0]["type"] as? String == "image" && content[1]["text"] as? String == "질문"
          && line.hasSuffix("\n"), "inputLine: 이미지 먼저, 질문 뒤, 한 줄")
    check(a.contains("--mcp-config"), "arguments: 김비서 MCP 설정")
    if let i = a.firstIndex(of: "--allowedTools") {
        let allowed = a[i + 1].split(separator: ",").map(String.init)
        check(allowed.contains("mcp__kimbiseo__jira_search") && allowed.contains("mcp__kimbiseo__wiki_search")
              && allowed.contains("mcp__claude_ai_Microsoft_365__outlook_email_search")
              && allowed.allSatisfy { $0.hasPrefix("mcp__kimbiseo__") || $0.hasPrefix("mcp__claude_ai_Microsoft_365__") }, "arguments: 허용 도구는 김비서·M365 조회만")
    } else { check(false, "arguments: 허용 도구 옵션") }
    check(!a.contains("--resume"), "arguments: 세션 없으면 resume 없음")
    let b = ClaudeCommand.arguments(sessionId: "s1", mcpConfigPath: "/c.json", systemPrompt: "sys")
    if let i = b.firstIndex(of: "--resume") { check(b[i + 1] == "s1", "arguments: resume 뒤 세션 ID") }
    else { check(false, "arguments: 세션 있으면 resume") }
}

// MARK: ClaudeResponse
do {
    let ok = #"{"type":"result","is_error":false,"result":"답","session_id":"s1"}"#
    check(ClaudeResponse.parse(stdout: Data(ok.utf8), exitCode: 0) == .success(text: "답", sessionId: "s1"), "parse: 성공")
    let stream = "{\"type\":\"system\",\"subtype\":\"init\"}\n{\"type\":\"assistant\"}\n{\"type\":\"result\",\"is_error\":false,\"result\":\"빨강\",\"session_id\":\"s9\"}\n"
    check(ClaudeResponse.parse(stdout: Data(stream.utf8), exitCode: 0) == .success(text: "빨강", sessionId: "s9"), "parse: stream-json 의 result 줄")
    let auth = #"{"is_error":true,"result":"Failed to authenticate: OAuth session expired","session_id":"x"}"#
    check(ClaudeResponse.parse(stdout: Data(auth.utf8), exitCode: 1) == .failure(.notLoggedIn), "parse: 로그인 만료 JSON")
    check(ClaudeResponse.parse(stdout: Data("Please run /login".utf8), exitCode: 1) == .failure(.notLoggedIn), "parse: JSON 아닌 로그인 안내")
    if case .failure(.malformed) = ClaudeResponse.parse(stdout: Data("segfault".utf8), exitCode: 139) { check(true, "") }
    else { check(false, "parse: 알 수 없는 출력은 malformed") }
}

// MARK: ToolErrorCode
check(ToolErrorCode.detect(in: "AUTH_EXPIRED:jira\nJira 연결이 만료됐어요") == [.authExpired("jira")], "detect: 만료")
check(ToolErrorCode.detect(in: "NETWORK_UNREACHABLE:jira, NOT_CONNECTED:hr") == [.networkUnreachable("jira"), .notConnected("hr")], "detect: 여러 개")
check(ToolErrorCode.detect(in: "정상 답변") == [], "detect: 없음")

// MARK: ReportSchedule
do {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
    func at(_ day: Int, _ h: Int, _ m: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
    }
    let yesterday = "2026-10-20", today = "2026-10-21"
    check(!ReportSchedule.shouldRun(now: at(21, 9, 59), lastRunDay: nil, hour: 10, minute: 0, calendar: cal), "schedule: 10시 전")
    check(ReportSchedule.shouldRun(now: at(21, 10, 0), lastRunDay: nil, hour: 10, minute: 0, calendar: cal), "schedule: 10시 정각")
    check(!ReportSchedule.shouldRun(now: at(21, 15, 0), lastRunDay: today, hour: 10, minute: 0, calendar: cal), "schedule: 오늘 이미 실행")
    check(ReportSchedule.shouldRun(now: at(21, 15, 0), lastRunDay: yesterday, hour: 10, minute: 0, calendar: cal), "schedule: 잠자기 후 깨어남")
    check(!ReportSchedule.shouldRun(now: at(21, 0, 5), lastRunDay: yesterday, hour: 10, minute: 0, calendar: cal), "schedule: 자정 직후")
    check(ReportSchedule.dayString(at(21, 23, 59), calendar: cal) == today, "schedule: 날짜 문자열")
}

// MARK: Connections JSON (kimbiseo 출력 형식)
do {
    let status = #"[{"system":"jira","name":"Jira","group":"ad","status":"expired"},{"system":"wiki","name":"Wiki","group":"ad","status":"unavailable"}]"#
    let s = try? JSONDecoder().decode([SystemStatus].self, from: Data(status.utf8))
    check(s?.map(\.status) == [.expired, .unavailable], "status: 디코딩")
    let connect = #"[{"system":"jira","status":"network_unreachable","message":"사내망 연결을 확인해 주세요"}]"#
    let c = try? JSONDecoder().decode([ConnectResult].self, from: Data(connect.utf8))
    check(c?.first?.status == "network_unreachable", "connect: 디코딩")
    check(ConnectTarget.group("ad").arguments == ["connect", "--group", "ad"], "connect: 그룹 인자")
}

// MARK: Alarm
do {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
    // 2026-10-24 토, 2026-10-26 월
    func at(_ day: Int, _ h: Int, _ m: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))! }
    let weekday = Alarm(title: "t", prompt: "p", hour: 9, minute: 30, repeatRule: .weekdays)
    check(!weekday.shouldRun(now: at(24, 10, 0), calendar: cal), "alarm: 평일 알림은 토요일에 안 울림")
    check(weekday.shouldRun(now: at(26, 9, 30), calendar: cal), "alarm: 평일 알림 월요일 9:30")
    check(!weekday.shouldRun(now: at(26, 9, 29), calendar: cal), "alarm: 시각 전")
    var off = weekday; off.enabled = false
    check(!off.shouldRun(now: at(26, 10, 0), calendar: cal), "alarm: 꺼진 알림")
    let saturday = Alarm(title: "t", prompt: "p", hour: 8, minute: 0, repeatRule: .days([7]))
    check(saturday.shouldRun(now: at(24, 8, 1), calendar: cal), "alarm: 요일 선택(토)")
    let once = Alarm(title: "t", prompt: "p", hour: 14, minute: 0, repeatRule: .once("2026-10-26"))
    check(once.shouldRun(now: at(26, 15, 0), calendar: cal) && !once.shouldRun(now: at(27, 15, 0), calendar: cal), "alarm: 한 번은 그날만")
    var ran = weekday; ran.lastRunDay = "2026-10-26"
    check(!ran.shouldRun(now: at(26, 11, 0), calendar: cal), "alarm: 오늘 이미 실행")
    check(Alarm.Repeat.days([2, 4, 6]).description == "월·수·금", "alarm: 요일 표시")
    let encoded = try? JSONEncoder().encode([saturday, once])
    check(encoded.flatMap { try? JSONDecoder().decode([Alarm].self, from: $0) } == [saturday, once], "alarm: 저장 형식 왕복")
}

// MARK: ConnectorStatus
do {
    let ok = "claude.ai Google Docs: https://x - ✔ Connected\nclaude.ai Microsoft 365: https://microsoft365.mcp.claude.com/mcp - ✔ Connected"
    let need = "claude.ai Microsoft 365: https://microsoft365.mcp.claude.com/mcp - ! Needs authentication"
    check(ConnectorStatus.parse(output: ok, name: "Microsoft 365") == .connected, "connector: 연결됨")
    check(ConnectorStatus.parse(output: need, name: "Microsoft 365") == .disconnected, "connector: 인증 필요")
    check(ConnectorStatus.parse(output: "", name: "Microsoft 365") == .disconnected, "connector: 목록에 없음")
}

// MARK: ChatMessage
do {
    let old = #"[{"id":"6F1D6F5E-0000-0000-0000-000000000001","role":"user","text":"hi","date":0}]"#
    let m = try? JSONDecoder().decode([ChatMessage].self, from: Data(old.utf8))
    check(m?.first?.images == [], "chat: 예전 대화 기록도 읽음 (이미지 없음)")
}

// MARK: Reminder
do {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var q = ReminderQueue()
    let a = Reminder(title: "미완료 Jira 보고", summary: "미완료 Jira 3건", firedAt: t0)
    let b = Reminder(title: "메일", summary: "답장 필요 2통", firedAt: t0.addingTimeInterval(60))
    q.add(a); q.add(b)
    check(q.visible(now: t0.addingTimeInterval(61)).map(\.id) == [b.id, a.id], "reminder: 최근 것이 위")
    q.snooze(a.id, minutes: 10, now: t0.addingTimeInterval(120))
    check(q.visible(now: t0.addingTimeInterval(120 + 599)).map(\.id) == [b.id], "reminder: 다시 알림 전에는 안 보임")
    check(q.visible(now: t0.addingTimeInterval(120 + 600)).map(\.id).contains(a.id), "reminder: 다시 알림 시각이 되면 보임")
    q.dismiss(b.id)
    check(!q.items.contains { $0.id == b.id }, "reminder: 확인하면 사라짐")
    q.add(b)
    q.dismissVisible(now: t0.addingTimeInterval(130))
    check(q.items.map(\.id) == [a.id], "reminder: 모두 확인은 보이는 카드만 (미룬 카드는 남음)")
    let data = try? JSONEncoder().encode(q)
    check(data.flatMap { try? JSONDecoder().decode(ReminderQueue.self, from: $0) } == q, "reminder: 저장 형식 왕복")
    check(Reminder.summary(of: "\n  미완료 Jira 3건\nPRICING-1") == "미완료 Jira 3건", "reminder: 첫 줄 요약")
}

// MARK: Hotkey, GitHub
do {
    check(Hotkey.default.display == "⌃⌥⇧⌘ Space", "hotkey: 기본 표기")
    check(Hotkey(keyCode: 40, modifiers: Hotkey.control | Hotkey.option).display == "⌃⌥ K", "hotkey: ⌃⌥K 표기")
    check(!Hotkey(keyCode: 40, modifiers: Hotkey.shift).isValid, "hotkey: Shift 만은 안 됨")
    check(GitHubLogin.code(in: "! First copy your one-time code: 1A2B-3C4D\nPress Enter") == "1A2B-3C4D", "github: 한 번용 코드 찾기")
    let prs = #"[{"id":7,"repo":"org/gmkt-dc-api","number":1290,"title":"t","author":"kim","url":"https://g/pull/1290","updated":"2026-10-22T10:42"}]"#
    check((try? JSONDecoder().decode([PullRequest].self, from: Data(prs.utf8)))?.first?.number == 1290, "github: PR 디코딩")
}

// MARK: Trigger
do {
    let t = Alarm.defaultReviewRequestTrigger()
    check(!t.shouldRun(now: Date(), calendar: .current), "trigger: 시각 판단으로는 울리지 않음")
    let old = #"[{"id":"6F1D6F5E-0000-0000-0000-000000000002","title":"t","prompt":"p","hour":9,"minute":0,"repeatRule":{"daily":{}},"enabled":true}]"#
    check((try? JSONDecoder().decode([Alarm].self, from: Data(old.utf8)))?.first?.trigger == nil, "trigger: 예전 알림 파일도 읽음")
    let enc = try? JSONEncoder().encode([t])
    check(enc.flatMap { try? JSONDecoder().decode([Alarm].self, from: $0) }?.first?.trigger == t.trigger, "trigger: 저장 형식 왕복")
    let a = EventItem(key: "1", title: "a", summary: "", url: ""), b = EventItem(key: "2", title: "b", summary: "", url: "")
    check(TriggerDiff.newItems(current: [a, b], seen: nil).isEmpty, "trigger: 처음엔 기준만 잡고 알리지 않음")
    check(TriggerDiff.newItems(current: [a, b], seen: ["1"]) == [b], "trigger: 새 항목만")
    check(TriggerEvent.events(for: "github").count == 3 && TriggerEvent.systems == ["github", "deploy", "jira"], "trigger: 이벤트 목록")
}

// MARK: AppSettings
do {
    let old = #"{"repoDir":"/r","claudePath":"/c","uvPath":"/u","reportHour":10,"reportMinute":0,"lastReportDay":"2026-10-21"}"#
    let s = try? JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
    check(s?.assistantName == "김비서" && s?.repoDir == "/r" && s?.lastReportDay == "2026-10-21", "settings: 예전 파일도 읽음 (이름 기본값)")
}

print("passed: \(passed), failed: \(failures)")
exit(failures == 0 ? 0 : 1)
