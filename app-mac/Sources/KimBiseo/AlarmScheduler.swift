import AppKit
import KimBiseoCore

/// 알림 실행기. 1분마다, 그리고 잠자기에서 깨어날 때 실행할 알림을 찾는다.
@MainActor
final class AlarmScheduler {
    private let model: AppModel
    private let notifier: Notifier
    private let reminders: ReminderCenter
    private let triggers: TriggerWatcher
    private var timer: Timer?

    init(model: AppModel, notifier: Notifier, reminders: ReminderCenter, triggers: TriggerWatcher) {
        self.model = model
        self.notifier = notifier
        self.reminders = reminders
        self.triggers = triggers
    }

    func start() {
        model.runAlarmNow = { [weak self] alarm in
            guard let self else { return }
            if alarm.trigger != nil {
                self.model.markRunning(alarm.id)
                Task {
                    let result = await self.triggers.check(alarm)
                    self.model.markDone(alarm.id, result.message, failed: result.failed)
                }
            } else {
                self.run(alarm)
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkAll() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.checkAll() }
        }
        checkAll()
    }

    private func checkAll() {
        let now = Date()
        for alarm in model.alarms where alarm.shouldRun(now: now, calendar: .current) {
            run(alarm)
        }
    }

    private func run(_ alarm: Alarm) {
        // 실행하는 순간 기록한다. 실패해도 같은 날 다시 시도하지 않는다.
        let today = ReportSchedule.dayString(Date(), calendar: .current)
        if let i = model.alarms.firstIndex(where: { $0.id == alarm.id }) {
            model.alarms[i].lastRunDay = today
            if case .once = alarm.repeatRule { model.alarms[i].enabled = false }
        }
        if alarm.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if alarm.toMac { notifier.send(title: "🔔 \(alarm.title)", body: "잊지 마세요.") }
            if alarm.toPanel { reminders.add(title: alarm.title, text: "잊지 마세요: \(alarm.title)", failed: false) }
            model.markDone(alarm.id, "알림 창에 보냈어요")
            return
        }
        guard let prompt = AlarmStore.resolvePrompt(alarm, settings: model.settings) else {
            if alarm.toMac { notifier.send(title: alarm.title, body: "알림 내용을 읽지 못했어요.") }
            if alarm.toPanel { reminders.add(title: alarm.title, text: "알림 내용을 읽지 못했어요.", failed: true) }
            model.markDone(alarm.id, "알림 내용을 읽지 못했어요", failed: true)
            return
        }
        model.markRunning(alarm.id)
        model.chat.runReport(title: alarm.title, prompt: prompt) { [notifier, reminders, model] response in
            switch response {
            case .success(let text, _):
                let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
                if alarm.toMac { notifier.send(title: "🔔 \(alarm.title)", body: lines.prefix(4).joined(separator: "\n")) }
                if alarm.toPanel { reminders.add(title: alarm.title, text: text, failed: false) }
                model.markDone(alarm.id, "끝났어요. 결과는 알림 창과 채팅에 있어요")
            case .failure(let failure):
                if alarm.toMac { notifier.send(title: "🔔 \(alarm.title) 실패", body: failure.message) }
                if alarm.toPanel { reminders.add(title: alarm.title, text: failure.message, failed: true) }
                model.markDone(alarm.id, failure.message, failed: true)
            }
        }
    }
}
