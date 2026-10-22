import Foundation

/// 매일 보고를 지금 실행할지 판단한다. 잠자기로 보고 시각을 놓쳤어도 깨어난 뒤 그날 1회 실행된다.
public enum ReportSchedule {
    public static func shouldRun(now: Date, lastRunDay: String?, hour: Int, minute: Int, calendar: Calendar) -> Bool {
        let today = dayString(now, calendar: calendar)
        if lastRunDay == today { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return nowMinutes >= hour * 60 + minute
    }

    public static func dayString(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
