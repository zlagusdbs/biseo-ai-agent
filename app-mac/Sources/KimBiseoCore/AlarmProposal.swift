import Foundation

/// 채팅 답변에 붙어 오는 알림 등록 제안. Claude 는 직접 저장하지 않고 아래 블록으로 제안만 하고,
/// 사용자가 [알림에 등록]을 눌러야 알림 메뉴에 들어간다.
///
///     ```kimbiseo-alarm
///     [{"title":"1:1 요청","hour":9,"minute":0,"repeat":"daily","prompt":""}]
///     ```
public enum AlarmProposal {
    private struct Item: Decodable {
        let title: String
        let hour: Int
        let minute: Int?
        let `repeat`: String?
        let prompt: String?
    }

    private static let block = try! NSRegularExpression(pattern: "```kimbiseo-alarm[ \\t]*\\n(.*?)```",
                                                        options: [.dotMatchesLineSeparators])

    /// 답변에서 제안 블록을 떼어 낸다. 블록이 없거나 잘못됐으면 알림 없이 원문(블록만 뺀 글)을 돌려준다.
    public static func extract(from text: String) -> (text: String, alarms: [Alarm]) {
        let range = NSRange(text.startIndex..., in: text)
        var alarms: [Alarm] = []
        for match in block.matches(in: text, range: range) {
            guard let body = Range(match.range(at: 1), in: text),
                  let items = try? JSONDecoder().decode([Item].self, from: Data(text[body].utf8)) else { continue }
            alarms += items.compactMap(alarm)
        }
        let clean = block.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (clean, alarms)
    }

    private static func alarm(_ item: Item) -> Alarm? {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let minute = item.minute ?? 0
        guard !title.isEmpty, (0...23).contains(item.hour), (0...59).contains(minute),
              let rule = repeatRule(item.repeat ?? "daily") else { return nil }
        return Alarm(title: title, prompt: item.prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                     hour: item.hour, minute: minute, repeatRule: rule)
    }

    /// "daily" / "weekdays" / "days:2,4" (1=일 … 7=토) / "once:2026-10-23"
    public static func repeatRule(_ text: String) -> Alarm.Repeat? {
        let value = text.trimmingCharacters(in: .whitespaces)
        switch value {
        case "daily": return .daily
        case "weekdays": return .weekdays
        default:
            if value.hasPrefix("days:") {
                let days = value.dropFirst(5).split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                return !days.isEmpty && days.allSatisfy { (1...7).contains($0) } ? .days(Array(Set(days)).sorted()) : nil
            }
            if value.hasPrefix("once:") {
                let day = String(value.dropFirst(5))
                return day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil ? .once(day) : nil
            }
            return nil
        }
    }
}
