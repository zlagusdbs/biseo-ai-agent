import Foundation
import KimBiseoCore

enum SidebarItem: String, CaseIterable, Identifiable {
    case chat, connections, alarms, settings
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .connections: return "powerplug"
        case .alarms: return "bell"
        case .settings: return "gearshape"
        }
    }

    var title: String {
        switch self {
        case .chat: return "채팅"
        case .connections: return "연결"
        case .alarms: return "알림"
        case .settings: return "설정"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selected: SidebarItem = .chat
    @Published var settings: AppSettings {
        didSet { AppPaths.saveSettings(settings) }
    }

    @Published var alarms: [Alarm] {
        didSet { AlarmStore.save(alarms) }
    }
    /// 알림을 지금 바로 실행 (AlarmScheduler 가 연결한다).
    var runAlarmNow: (Alarm) -> Void = { _ in }

    @Published private(set) var systems: [SystemStatus] = []
    /// Microsoft 365 커넥터 상태. nil 이면 확인 중.
    @Published private(set) var microsoft365: SystemStatus.Status?
    @Published private(set) var connectionError: String?
    @Published private(set) var isLoadingSystems = false

    lazy var chat = ChatSession { [weak self] in self?.settings ?? .default }

    init() {
        let loaded = AppPaths.loadSettings()
        settings = loaded
        alarms = AlarmStore.load(settings: loaded)
        // 예전에 따로 돌던 GitHub 리뷰 요청 감시를 트리거 알림 하나로 옮긴다 (한 번만).
        if !UserDefaults.standard.bool(forKey: "migratedReviewTrigger") {
            UserDefaults.standard.set(true, forKey: "migratedReviewTrigger")
            if !alarms.contains(where: { $0.trigger?.event == "github.review_requested" }) {
                let trigger = Alarm.defaultReviewRequestTrigger()
                TriggerWatcher.migrateGitHubSeen(to: trigger)
                alarms.append(trigger)
            }
        }
        AlarmStore.save(alarms)
    }

    /// 알림 추가·수정. 시각 알림 먼저, 트리거는 아래로 정렬한다.
    func save(_ alarm: Alarm) {
        if let i = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[i] = alarm
        } else {
            alarms.append(alarm)
        }
        alarms.sort { a, b in
            if (a.trigger == nil) != (b.trigger == nil) { return a.trigger == nil }
            return (a.hour, a.minute) < (b.hour, b.minute)
        }
    }

    /// 채팅에서 제안된 알림을 등록한다. 이미 등록한 것은 건너뛴다.
    func register(_ proposed: [Alarm]) {
        for var alarm in proposed where !alarms.contains(where: { $0.id == alarm.id }) {
            alarm.resetSchedule(now: Date(), calendar: .current)
            save(alarm)
        }
    }

    func refreshSystems() async {
        microsoft365 = nil
        Task { microsoft365 = await ConnectorStatus.check(name: ConnectorStatus.microsoft365, settings: settings) }
        isLoadingSystems = true
        defer { isLoadingSystems = false }
        do {
            systems = try await KimbiseoCLI.status(settings: settings)
            connectionError = nil
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func connect(_ target: ConnectTarget, username: String, secret: String) async -> [ConnectResult] {
        defer { Task { await refreshSystems() } }
        do {
            return try await KimbiseoCLI.connect(target: target, username: username, secret: secret, settings: settings)
        } catch {
            return [ConnectResult(system: "", status: "error", message: error.localizedDescription)]
        }
    }

    func status(of system: String) -> SystemStatus.Status? {
        systems.first { $0.system == system }?.status
    }
}
