import Foundation

/// 오른쪽 아래 "김비서 알림" 창의 카드 하나.
public struct Reminder: Identifiable, Codable, Equatable {
    public let id: UUID
    public let title: String
    public let summary: String
    public let firedAt: Date
    public let failed: Bool
    /// 다시 알림으로 미뤄 둔 시각. nil 이면 지금 보인다.
    public var snoozedUntil: Date?
    /// 카드에서 바로 열 링크 (예: PR). 있으면 [자세히] 대신 [열기] 버튼.
    public var url: String?

    public init(id: UUID = UUID(), title: String, summary: String, firedAt: Date, failed: Bool = false,
                snoozedUntil: Date? = nil, url: String? = nil) {
        self.url = url
        self.id = id
        self.title = title
        self.summary = summary
        self.firedAt = firedAt
        self.failed = failed
        self.snoozedUntil = snoozedUntil
    }

    /// 결과 첫 줄(비어 있지 않은 줄)을 요약으로 쓴다.
    public static func summary(of text: String) -> String {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
    }
}

/// 미리 알림 목록. 추가·확인·다시 알림과 지금 보일 카드를 계산한다.
public struct ReminderQueue: Codable, Equatable {
    public static let snoozeChoices = [5, 10, 30, 60]

    public private(set) var items: [Reminder] = []

    public init(items: [Reminder] = []) { self.items = items }

    public mutating func add(_ reminder: Reminder) { items.append(reminder) }

    public mutating func dismiss(_ id: UUID) { items.removeAll { $0.id == id } }

    public mutating func dismissVisible(now: Date) { items.removeAll { $0.isVisible(now: now) } }

    public mutating func snooze(_ id: UUID, minutes: Int, now: Date) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].snoozedUntil = now.addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// 지금 보일 카드 (최근 것이 위).
    public func visible(now: Date) -> [Reminder] {
        items.filter { $0.isVisible(now: now) }.sorted { $0.firedAt > $1.firedAt }
    }
}

extension Reminder {
    func isVisible(now: Date) -> Bool { snoozedUntil.map { $0 <= now } ?? true }
}
