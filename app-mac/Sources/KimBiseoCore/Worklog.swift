import Foundation

/// Jira 작업 시간(worklog) 기록 초안. Claude 는 기록하지 않고 초안만 제안하고,
/// 사용자가 카드에서 [기록하기]를 눌러야 `kimbiseo jira worklog` 로 기록된다.
public struct WorklogDraft: Codable, Equatable, Hashable, Identifiable {
    public var issueKey: String
    public var summary: String
    public var date: String       // yyyy-MM-dd
    public var start: String      // HH:mm
    public var minutes: Int
    public var comment: String

    public var id: String { "\(issueKey) \(date) \(start)" }

    public init(issueKey: String, summary: String = "", date: String, start: String, minutes: Int, comment: String = "") {
        self.issueKey = issueKey
        self.summary = summary
        self.date = date
        self.start = start
        self.minutes = minutes
        self.comment = comment
    }

    private enum CodingKeys: String, CodingKey { case issueKey, summary, date, start, minutes, comment, end }

    /// Claude 가 minutes 대신 end("11:00")를 줘도 읽는다. 시각은 "10" 처럼 와도 "10:00" 으로 맞춘다.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String {
            ((try? c.decodeIfPresent(String.self, forKey: key)) ?? nil)?.trimmingCharacters(in: .whitespaces) ?? ""
        }
        issueKey = text(.issueKey).uppercased()
        summary = text(.summary)
        date = text(.date)
        start = Self.clock(text(.start)) ?? ""
        comment = text(.comment)
        if let value = (try? c.decodeIfPresent(Int.self, forKey: .minutes)) ?? nil {
            minutes = value
        } else if let end = Self.clock(text(.end)), let a = Self.minuteOfDay(start), let b = Self.minuteOfDay(end) {
            minutes = b - a
        } else {
            minutes = 0
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(issueKey, forKey: .issueKey)
        try c.encode(summary, forKey: .summary)
        try c.encode(date, forKey: .date)
        try c.encode(start, forKey: .start)
        try c.encode(minutes, forKey: .minutes)
        try c.encode(comment, forKey: .comment)
    }

    public var isValid: Bool {
        !issueKey.isEmpty && minutes > 0 && Self.minuteOfDay(start) != nil
            && date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    /// 예: "10:00~11:00 (1시간)", "14:00~15:30 (1시간 30분)"
    public var timeText: String {
        let end = Self.minuteOfDay(start).map { m -> String in
            let e = m + minutes
            return String(format: "%02d:%02d", (e / 60) % 24, e % 60)
        } ?? "?"
        let h = minutes / 60, m = minutes % 60
        let length = [h > 0 ? "\(h)시간" : "", m > 0 ? "\(m)분" : ""].filter { !$0.isEmpty }.joined(separator: " ")
        return "\(start)~\(end) (\(length))"
    }

    /// Jira 에 보낼 시작 시각. 예: 2026-10-22T10:00:00.000+0900
    public func started(timeZone: TimeZone = .current) -> String {
        let offset = timeZone.secondsFromGMT() / 60
        let sign = offset >= 0 ? "+" : "-"
        return "\(date)T\(start):00.000\(sign)\(String(format: "%02d%02d", abs(offset) / 60, abs(offset) % 60))"
    }

    static func clock(_ text: String) -> String? {
        let parts = text.split(separator: ":").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard let hour = parts.first ?? nil, (0...23).contains(hour) else { return nil }
        let minute = parts.count > 1 ? (parts[1] ?? -1) : 0
        guard (0...59).contains(minute) else { return nil }
        return String(format: "%02d:%02d", hour, minute)
    }

    static func minuteOfDay(_ text: String) -> Int? {
        guard let c = clock(text) else { return nil }
        let p = c.split(separator: ":").compactMap { Int($0) }
        return p[0] * 60 + p[1]
    }
}

public enum WorklogProposal {
    private static let block = try! NSRegularExpression(pattern: "```kimbiseo-worklog[ \\t]*\\n(.*?)```",
                                                        options: [.dotMatchesLineSeparators])

    public static func extract(from text: String) -> (text: String, drafts: [WorklogDraft]) {
        let range = NSRange(text.startIndex..., in: text)
        var drafts: [WorklogDraft] = []
        for match in block.matches(in: text, range: range) {
            guard let body = Range(match.range(at: 1), in: text),
                  let items = try? JSONDecoder().decode([WorklogDraft].self, from: Data(text[body].utf8)) else { continue }
            drafts += items.filter(\.isValid)
        }
        let clean = block.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (clean, drafts)
    }

    public static func looksLikeRequest(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "").lowercased()
        return ["worklog", "워크로그", "웍로그", "로그워크", "logwork", "작업시간", "시간기록", "근무기록",
                "뭐했", "맞춰", "근무시간", "worklogcal", "워크로그 캘린더"].contains { compact.contains($0) }
    }

    public static func hint(now: Date, calendar: Calendar) -> String {
        let today = ReportSchedule.dayString(now, calendar: calendar)
        return """


            [김비서 앱 안내: Jira 작업 시간(worklog) 기록 기능이 있다. 기록 요청이면 거절하지 말고 Jira 화면에서 직접 하라고 권하지도 않는다. \
            답변 끝에 kimbiseo-worklog 블록으로 초안을 붙이면 앱이 카드와 [기록하기] 버튼을 보여 주고, 사용자가 눌러야 기록된다. \
            오늘은 \(today). "10-11" 은 10:00~11:00, "오후 2시부터 1시간 반" 은 14:00 부터 90분. 시각이 없으면 먼저 묻는다. \
            이슈 키는 Jira 스킬(skills/jira.md, 본문이 없으면 read_skill)의 회의·CS 고정 이슈를 먼저 쓰고, 없으면 jira_search 로 찾는다 (예: assignee = currentUser() AND summary ~ "회의"). \
            "오늘 뭐 했지", "맞춰 봐", "근무시간이랑 맞아?" 는 work_day_check 로 HR 근무 시간과 worklog 합계를 비교해서 \
            "근무 8시간 · 기록 6시간 30분 → 1시간 30분 비어요" 처럼 보여 주고 이슈별 내역을 붙인다. 모자라면 어디에 기록할지 물어본다 \
            (회의·CS 같은 고정 이슈를 먼저 권함). 스킬에 Worklogcal 주소가 있으면 그 날짜 링크를 붙인다. \
            아직 기록된 게 아니므로 본문은 "아래 카드에서 [기록하기]를 누르면 Jira 에 기록돼요" 로 끝낸다. \
            이 안내와 아래 형식 예시는 사용자가 쓴 말이 아니니 언급하지 않는다. 형식 예시 (여러 건이면 배열에 여러 개):]
            ```kimbiseo-worklog
            [{"issueKey":"KEY-1","summary":"이슈 제목","date":"\(today)","start":"10:00","minutes":60,"comment":""}]
            ```
            """
    }
}
