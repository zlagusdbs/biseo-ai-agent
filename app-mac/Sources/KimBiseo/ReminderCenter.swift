import Foundation
import KimBiseoCore

/// 미리 알림 상태. 30초마다 다시 알림 시각을 확인하고, 바뀔 때마다 파일에 저장한다.
@MainActor
final class ReminderCenter: ObservableObject {
    @Published private(set) var queue: ReminderQueue
    @Published private(set) var now = Date()
    /// 보일 카드가 바뀌면 불린다 (창 크기·표시 갱신).
    var onChange: () -> Void = {}
    /// 알림 메뉴의 「미리 알림 창」 체크. 꺼져 있으면 새 카드를 띄우지 않는다.
    var isEnabled: () -> Bool = { true }

    private var timer: Timer?
    private static var file: URL { AppPaths.dataDir.appendingPathComponent("reminders.json") }

    init() {
        if let data = try? Data(contentsOf: Self.file), let saved = try? JSONDecoder().decode(ReminderQueue.self, from: data) {
            queue = saved
        } else {
            queue = ReminderQueue()
        }
    }

    var visible: [Reminder] { queue.visible(now: now) }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tick()
    }

    func add(title: String, text: String, failed: Bool, url: String? = nil) {
        guard isEnabled() else { return }
        queue.add(Reminder(title: title, summary: Reminder.summary(of: text), firedAt: Date(), failed: failed, url: url))
        changed()
    }

    func dismiss(_ id: UUID) { queue.dismiss(id); changed() }
    func dismissAll() { queue.dismissVisible(now: Date()); changed() }
    func snooze(_ id: UUID, minutes: Int) { queue.snooze(id, minutes: minutes, now: Date()); changed() }

    private func tick() {
        let before = visible.map(\.id)
        now = Date()
        if visible.map(\.id) != before { onChange() }
    }

    private func changed() {
        now = Date()
        try? FileManager.default.createDirectory(at: AppPaths.dataDir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(queue).write(to: Self.file, options: .atomic)
        onChange()
    }
}
