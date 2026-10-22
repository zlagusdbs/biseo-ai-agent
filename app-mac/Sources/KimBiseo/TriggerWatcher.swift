import Foundation
import KimBiseoCore

/// 트리거 알림 확인기. 5분마다 켜진 트리거 알림의 이벤트를 조회해서 새로 생긴 항목만 알린다.
/// 내용(prompt)이 있으면 김비서가 그 일을 해서 결과를 카드로, 없으면 이벤트 자체를 카드로 보여 준다.
@MainActor
final class TriggerWatcher {
    private let model: AppModel
    private let notifier: Notifier
    private let reminders: ReminderCenter
    private var timer: Timer?
    private var checking: Set<UUID> = []
    private static var seenFile: URL { AppPaths.dataDir.appendingPathComponent("trigger-seen.json") }

    init(model: AppModel, notifier: Notifier, reminders: ReminderCenter) {
        self.model = model
        self.notifier = notifier
        self.reminders = reminders
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkAll() }
        }
        Task { try? await Task.sleep(nanoseconds: 10_000_000_000); await checkAll() }
    }

    func checkAll() async {
        for alarm in model.alarms where alarm.enabled && alarm.trigger != nil {
            await check(alarm)
        }
    }

    /// 한 알림 확인. [지금 실행] 에서도 부르고, 결과를 한 줄로 돌려준다 (알림 목록에 잠깐 보임).
    @discardableResult
    func check(_ alarm: Alarm) async -> (message: String, failed: Bool) {
        guard let trigger = alarm.trigger, !checking.contains(alarm.id) else { return ("이미 확인 중이에요", false) }
        checking.insert(alarm.id)
        defer { checking.remove(alarm.id) }
        guard let items = try? await KimbiseoCLI.events(trigger.event, settings: model.settings) else {
            return ("확인하지 못했어요. 연결 메뉴를 확인해 주세요", true)
        }

        var seenAll = Self.loadSeen()
        let key = alarm.id.uuidString
        let firstTime = seenAll[key] == nil
        let fresh = TriggerDiff.newItems(current: items, seen: seenAll[key].map(Set.init))
        seenAll[key] = Array(Set(seenAll[key] ?? []).union(items.map(\.key)))
        Self.saveSeen(seenAll)

        for item in fresh {
            notify(alarm, item)
        }
        if firstTime { return ("처음이라 지금 있는 \(items.count)건을 기준으로 잡았어요", false) }
        return fresh.isEmpty ? ("새로 생긴 것 없어요", false) : ("새로 \(fresh.count)건, 알림 창에 보냈어요", false)
    }

    private func notify(_ alarm: Alarm, _ item: EventItem) {
        let prompt = alarm.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            if alarm.toMac { notifier.send(title: "🔔 \(item.title)", body: item.summary) }
            if alarm.toPanel { reminders.add(title: item.title, text: item.summary, failed: false, url: item.url.isEmpty ? nil : item.url) }
            return
        }
        let context = "다음 이벤트가 생겼다.\n- \(item.title)\n- \(item.summary)\n- 링크: \(item.url)\n\n요청: \(prompt)"
        model.chat.runReport(title: "\(alarm.title) · \(item.title)", prompt: context) { [notifier, reminders] response in
            switch response {
            case .success(let text, _):
                if alarm.toMac { notifier.send(title: "🔔 \(item.title)", body: Reminder.summary(of: text)) }
                if alarm.toPanel { reminders.add(title: item.title, text: text, failed: false, url: item.url.isEmpty ? nil : item.url) }
            case .failure(let failure):
                if alarm.toMac { notifier.send(title: "🔔 \(item.title)", body: item.summary) }
                if alarm.toPanel { reminders.add(title: item.title, text: failure.message, failed: true, url: item.url.isEmpty ? nil : item.url) }
            }
        }
    }

    /// 예전 GitHub 리뷰 요청 감시가 기억하던 PR 을 새 트리거 알림의 기준으로 옮긴다 (다시 알리지 않게).
    static func migrateGitHubSeen(to alarm: Alarm) {
        let old = AppPaths.dataDir.appendingPathComponent("github-seen.json")
        guard let data = try? Data(contentsOf: old), let ids = try? JSONDecoder().decode([Int].self, from: data) else { return }
        var seen = loadSeen()
        seen[alarm.id.uuidString] = ids.map(String.init)
        saveSeen(seen)
        try? FileManager.default.removeItem(at: old)
    }

    private static func loadSeen() -> [String: [String]] {
        guard let data = try? Data(contentsOf: seenFile),
              let seen = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
        return seen
    }

    private static func saveSeen(_ seen: [String: [String]]) {
        try? FileManager.default.createDirectory(at: AppPaths.dataDir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(seen).write(to: seenFile, options: .atomic)
    }
}
