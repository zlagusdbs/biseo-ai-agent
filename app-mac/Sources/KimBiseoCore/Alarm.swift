import Foundation

/// 사용자가 정한 시각에 김비서에게 시킬 일.
public struct Alarm: Identifiable, Codable, Equatable {
    public enum Repeat: Codable, Equatable {
        case daily
        case weekdays                 // 월~금
        case days([Int])              // Calendar weekday: 1=일 … 7=토
        case once(String)             // yyyy-MM-dd

        public var description: String {
            switch self {
            case .daily: return "매일"
            case .weekdays: return "평일"
            case .days(let days):
                let names = ["", "일", "월", "화", "수", "목", "금", "토"]
                return days.sorted().map { names[$0] }.joined(separator: "·")
            case .once(let day): return day
            }
        }
    }

    /// prompt 가 이 값이면 shared/prompts/daily-report.md 내용을 쓴다.
    public static let dailyReportPrompt = "{{daily-report}}"

    public var id: UUID
    public var title: String
    public var prompt: String
    public var hour: Int
    public var minute: Int
    public var repeatRule: Repeat
    public var enabled: Bool
    public var lastRunDay: String?
    /// 있으면 시각 대신 이 이벤트가 생길 때 울린다 (hour·minute·repeatRule 은 쓰지 않음).
    public var trigger: Trigger?

    public init(id: UUID = UUID(), title: String, prompt: String, hour: Int, minute: Int,
                repeatRule: Repeat, enabled: Bool = true, lastRunDay: String? = nil, trigger: Trigger? = nil) {
        self.trigger = trigger
        self.id = id
        self.title = title
        self.prompt = prompt
        self.hour = hour
        self.minute = minute
        self.repeatRule = repeatRule
        self.enabled = enabled
        self.lastRunDay = lastRunDay
    }

    public var timeText: String { String(format: "%02d:%02d", hour, minute) }

    public static func defaultReviewRequestTrigger() -> Alarm {
        Alarm(title: "GitHub · 리뷰 요청", prompt: "", hour: 0, minute: 0, repeatRule: .daily,
              trigger: Trigger(system: "github", event: "github.review_requested"))
    }

    public static func defaultDailyReport(hour: Int = 10, minute: Int = 0, lastRunDay: String? = nil) -> Alarm {
        Alarm(title: "미완료 Jira 보고", prompt: dailyReportPrompt, hour: hour, minute: minute,
              repeatRule: .daily, lastRunDay: lastRunDay)
    }

    /// 지금 실행할지. 오늘이 반복 대상 날이고, 시각이 지났고, 오늘 아직 안 돌렸으면 실행한다
    /// (잠자기로 시각을 놓쳤어도 깨어난 뒤 그날 1회).
    public func shouldRun(now: Date, calendar: Calendar) -> Bool {
        guard enabled, trigger == nil, appliesOn(now, calendar: calendar) else { return false }
        return ReportSchedule.shouldRun(now: now, lastRunDay: lastRunDay, hour: hour, minute: minute, calendar: calendar)
    }

    public func appliesOn(_ date: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        switch repeatRule {
        case .daily: return true
        case .weekdays: return (2...6).contains(weekday)
        case .days(let days): return days.contains(weekday)
        case .once(let day): return ReportSchedule.dayString(date, calendar: calendar) == day
        }
    }
}

public enum AlarmStore {
    public static var file: URL { AppPaths.dataDir.appendingPathComponent("alarms.json") }

    /// 저장된 알림. 처음이면 기존 10시 보고 설정으로 기본 알림을 만든다.
    public static func load(settings: AppSettings) -> [Alarm] {
        if let data = try? Data(contentsOf: file), let alarms = try? JSONDecoder().decode([Alarm].self, from: data) {
            return alarms
        }
        return [.defaultDailyReport(hour: settings.reportHour, minute: settings.reportMinute,
                                    lastRunDay: settings.lastReportDay)]
    }

    public static func save(_ alarms: [Alarm]) {
        try? FileManager.default.createDirectory(at: AppPaths.dataDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(alarms).write(to: file, options: .atomic)
    }

    public static func resolvePrompt(_ alarm: Alarm, settings: AppSettings) -> String? {
        guard alarm.prompt == Alarm.dailyReportPrompt else { return alarm.prompt }
        return try? String(contentsOf: AppPaths.sharedFile("prompts/daily-report.md", settings: settings), encoding: .utf8)
    }
}
