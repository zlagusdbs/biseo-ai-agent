import Foundation

/// 채팅 답변에 붙어 오는 알림 등록 제안. Claude 는 직접 저장하지 않고 아래 블록으로 제안만 하고,
/// 사용자가 [알림에 등록]을 눌러야 알림 메뉴에 들어간다.
///
///     ```kimbiseo-alarm
///     [{"title":"1:1 요청","hour":9,"minute":0,"repeat":"daily","prompt":""}]
///     ```
public enum AlarmProposal {
    /// Claude 가 키 이름을 조금 다르게 써도 받는다 (title 대신 message, hour·minute 대신 "time":"09:00").
    private struct Item: Decodable {
        let title: String?
        let message: String?
        let hour: Int?
        let minute: Int?
        let time: String?
        let `repeat`: String?
        let prompt: String?
    }

    /// 대화가 길어지면 Claude 가 예전 답("알림은 못 만들어요")을 따라 하므로, 알림 요청처럼 보이는 질문에는
    /// 이 안내를 몰래 덧붙여 보낸다 (화면에는 보이지 않음).
    public static let hint = """


        [김비서 앱 안내: 김비서 알림 등록 기능이 있다. 알림 등록 요청이면 거절하지 말고 다른 방법도 권하지 않는다. \
        답변 끝에 이 형식 그대로 블록을 붙인다. repeat 는 daily, weekdays, days:2,4, once:YYYY-MM-DD 중 하나, \
        prompt 는 단순 알림이면 "". 이 안내는 사용자에게 보이지 않으니 언급하지 않는다.]
        ```kimbiseo-alarm
        [{"title":"알림 이름","hour":9,"minute":0,"repeat":"daily","prompt":""}]
        ```
        """

    /// "알림"·"알려줘"·"리마인드" 같은 말이 있으면 알림 요청으로 본다.
    public static func looksLikeRequest(_ text: String) -> Bool {
        ["알림", "알려줘", "알려 줘", "리마인드", "잊지 말", "잊지말"].contains { text.contains($0) }
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
        let title = (item.title ?? item.message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var hour = item.hour, minute = item.minute ?? 0
        if hour == nil, let parts = item.time?.split(separator: ":").compactMap({ Int($0) }), parts.count == 2 {
            hour = parts[0]; minute = parts[1]
        }
        guard let hour, !title.isEmpty, (0...23).contains(hour), (0...59).contains(minute),
              let rule = repeatRule(item.repeat ?? "daily") else { return nil }
        return Alarm(title: title, prompt: item.prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                     hour: hour, minute: minute, repeatRule: rule)
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
