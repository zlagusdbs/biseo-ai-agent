import Foundation

/// 트리거 알림: 연결된 시스템에서 어떤 일이 생기면 울린다.
public struct Trigger: Codable, Equatable, Hashable {
    public var system: String   // github, deploy, jira
    public var event: String    // 예: github.my_pr_approved
    /// 몇 분마다 확인할지. nil 이면 5분 (예전 알림 파일 호환)
    public var intervalMinutes: Int?

    public static let defaultInterval = 5
    /// 고를 수 있는 주기 (분)
    public static let intervals = [1, 3, 5, 10, 30, 60]

    public var interval: Int { max(1, intervalMinutes ?? Self.defaultInterval) }

    public init(system: String, event: String, intervalMinutes: Int? = nil) {
        self.system = system
        self.event = event
        self.intervalMinutes = intervalMinutes
    }

    /// 지금 확인할 때인지. 한 번도 안 봤거나 마지막 확인에서 주기만큼 지났으면 true.
    public func isDue(lastChecked: Date?, now: Date) -> Bool {
        guard let lastChecked else { return true }
        return now.timeIntervalSince(lastChecked) >= Double(interval * 60) - 5   // 타이머 오차 5초 허용
    }
}

/// 고를 수 있는 이벤트 목록 (mcp-server 의 events.EVENTS 와 같은 id).
public struct TriggerEvent: Identifiable, Equatable {
    public let id: String
    public let system: String
    public let name: String

    public static let all: [TriggerEvent] = [
        TriggerEvent(id: "github.review_requested", system: "github", name: "리뷰어로 지정됐을 때"),
        TriggerEvent(id: "github.my_pr_approved", system: "github", name: "내 PR 이 승인됐을 때"),
        TriggerEvent(id: "github.my_pr_feedback", system: "github", name: "내 PR 에 변경 요청이나 댓글이 달렸을 때"),
        TriggerEvent(id: "deploy.approval_requested", system: "deploy", name: "내가 승인해야 할 배포가 생겼을 때"),
        TriggerEvent(id: "deploy.my_release_status", system: "deploy", name: "내 배포 상태가 바뀌었을 때"),
        TriggerEvent(id: "jira.assigned_to_me", system: "jira", name: "나에게 새 이슈가 할당됐을 때"),
        TriggerEvent(id: "jira.my_issue_status", system: "jira", name: "내 이슈 상태가 바뀌었을 때"),
    ]

    public static func events(for system: String) -> [TriggerEvent] { all.filter { $0.system == system } }
    public static func find(_ id: String) -> TriggerEvent? { all.first { $0.id == id } }
    public static var systems: [String] { all.reduce(into: [String]()) { if !$0.contains($1.system) { $0.append($1.system) } } }
}

/// `kimbiseo events <id>` 출력 한 줄.
public struct EventItem: Decodable, Equatable {
    public let key: String
    public let title: String
    public let summary: String
    public let url: String

    public init(key: String, title: String, summary: String, url: String) {
        self.key = key
        self.title = title
        self.summary = summary
        self.url = url
    }
}

/// 이전에 본 key 와 비교해 새로 생긴 항목을 고른다. 처음이면(기준 없음) 아무것도 알리지 않는다.
public enum TriggerDiff {
    public static func newItems(current: [EventItem], seen: Set<String>?) -> [EventItem] {
        guard let seen else { return [] }
        return current.filter { !seen.contains($0.key) }
    }
}
