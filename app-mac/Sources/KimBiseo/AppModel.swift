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
    /// 알림 그룹 이름 (보이는 순서). 비어 있는 그룹도 남는다.
    @Published var alarmGroups: [String] {
        didSet { AlarmStore.saveGroups(alarmGroups) }
    }
    /// 알림 실행 상태. 실행 중이면 목록에 돌아가는 표시를, 끝나면 결과 한 줄을 잠깐 보여 준다.
    enum AlarmRunState: Equatable {
        case running
        case done(String, failed: Bool)
    }
    @Published private(set) var alarmRuns: [UUID: AlarmRunState] = [:]

    func markRunning(_ id: UUID) { alarmRuns[id] = .running }

    /// 결과는 6초 보여 주고 지운다.
    func markDone(_ id: UUID, _ message: String, failed: Bool = false) {
        let state = AlarmRunState.done(message, failed: failed)
        alarmRuns[id] = state
        Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if alarmRuns[id] == state { alarmRuns[id] = nil }
        }
    }

    /// 알림을 지금 바로 실행 (AlarmScheduler 가 연결한다).
    var runAlarmNow: (Alarm) -> Void = { _ in }

    @Published private(set) var systems: [SystemStatus] = []
    /// Microsoft 365 커넥터 상태. nil 이면 확인 중.
    @Published private(set) var microsoft365: SystemStatus.Status?
    @Published private(set) var connectionError: String?
    @Published private(set) var isLoadingSystems = false

    lazy var chat = ChatSession(settings: { [weak self] in self?.settings ?? .default })

    init() {
        let loaded = AppPaths.loadSettings()
        settings = loaded
        alarms = AlarmStore.load(settings: loaded)
        alarmGroups = AlarmStore.loadGroups()
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
    /// 그룹 이름을 말했으면 그 그룹(없으면 새로 만듦)에, 아니면 같은 제목이 여러 개일 때(09·13·18시 같은) 그 제목으로 묶는다.
    func register(_ proposed: [Alarm]) {
        let titles = Dictionary(grouping: proposed, by: \.title)
        for var alarm in proposed where !alarms.contains(where: { $0.id == alarm.id }) {
            alarm.resetSchedule(now: Date(), calendar: .current)
            if let group = alarm.group {
                addGroup(group)
            } else if (titles[alarm.title]?.count ?? 0) > 1 {
                alarm.group = alarm.title
                addGroup(alarm.title)
            }
            save(alarm)
        }
    }

    // MARK: 알림 그룹

    /// 그룹 추가. 이미 있으면 그대로 둔다. 실제로 쓴 이름을 돌려준다.
    @discardableResult
    func addGroup(_ name: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if !alarmGroups.contains(name) { alarmGroups.append(name) }
        return name
    }

    func renameGroup(_ old: String, to new: String) {
        let new = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty, new != old, !alarmGroups.contains(new), let i = alarmGroups.firstIndex(of: old) else { return }
        alarmGroups[i] = new
        for j in alarms.indices where alarms[j].group == old { alarms[j].group = new }
    }

    /// 그룹만 지운다. 안의 알림은 "그룹 없음" 으로 옮긴다.
    func deleteGroup(_ name: String) {
        alarmGroups.removeAll { $0 == name }
        for j in alarms.indices where alarms[j].group == name { alarms[j].group = nil }
    }

    /// 끌어다 놓기: 알림을 그룹으로 옮긴다 (nil 이면 그룹 없음).
    func move(alarmID: UUID, to group: String?) {
        guard let i = alarms.firstIndex(where: { $0.id == alarmID }), alarms[i].group != group else { return }
        alarms[i].group = group
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
