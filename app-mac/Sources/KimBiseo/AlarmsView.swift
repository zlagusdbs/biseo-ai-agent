import KimBiseoCore
import SwiftUI

struct AlarmsView: View {
    @ObservedObject var model: AppModel
    @State private var editing: Alarm?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("알림").font(.headline)
                Spacer()
                Button {
                    editing = Alarm(title: "", prompt: "", hour: 9, minute: 0, repeatRule: .weekdays)
                } label: { Label("추가", systemImage: "plus") }
            }
            .padding(12)
            Divider()

            if model.alarms.isEmpty {
                Text("등록된 알림이 없어요. [추가]로 만들어 보세요.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 40)
                Spacer()
            } else {
                List {
                    ForEach($model.alarms) { $alarm in
                        HStack(alignment: .top, spacing: 10) {
                            Toggle("", isOn: $alarm.enabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                            VStack(alignment: .leading, spacing: 3) {
                                if let trigger = alarm.trigger {
                                    HStack(spacing: 6) {
                                        Label("트리거", systemImage: "bolt.fill").font(.callout.weight(.medium))
                                            .foregroundStyle(Color.orange)
                                        TriggerHelpIcon()
                                        Text("\(SystemNames.name(trigger.system)) · \(TriggerEvent.find(trigger.event)?.name ?? trigger.event)")
                                            .foregroundStyle(.secondary).lineLimit(1)
                                    }
                                } else {
                                    HStack {
                                        Text(alarm.timeText).font(.title3.monospacedDigit())
                                        Text(alarm.repeatRule.description).foregroundStyle(.secondary)
                                    }
                                }
                                Text(alarm.title.isEmpty ? "(제목 없음)" : alarm.title).font(.body.weight(.medium))
                                Text(alarm.prompt == Alarm.dailyReportPrompt ? "내 미완료 Jira 를 정리해서 보고"
                                     : alarm.prompt.isEmpty ? (alarm.trigger == nil ? "시각에 알림만" : "생기면 바로 알림") : alarm.prompt)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                if let last = alarm.lastRunDay {
                                    Text("마지막 실행 \(last)").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            Button { model.runAlarmNow(alarm) } label: { Image(systemName: "play.fill") }
                                .buttonStyle(.borderless).help(alarm.trigger == nil ? "지금 실행" : "지금 확인")
                            Button { editing = alarm } label: { Image(systemName: "pencil") }
                                .buttonStyle(.borderless).help("수정")
                            Button(role: .destructive) {
                                model.alarms.removeAll { $0.id == alarm.id }
                            } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).help("삭제")
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .task { if model.systems.isEmpty { await model.refreshSystems() } }
        .sheet(item: $editing) { alarm in
            AlarmEditor(alarm: alarm, systems: model.systems) { model.save($0) }
        }
    }
}

/// 알림 추가·수정: 언제(시각·반복), 무엇을(제목·김비서에게 시킬 내용).
struct AlarmEditor: View {
    enum RepeatKind: String, CaseIterable, Identifiable {
        case daily = "매일", weekdays = "평일", days = "요일 선택", once = "한 번"
        var id: String { rawValue }
    }

    enum Mode: String, CaseIterable, Identifiable {
        case time = "정해진 시각", trigger = "트리거"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var alarm: Alarm
    @State private var mode: Mode
    @State private var triggerSystem: String
    @State private var triggerEvent: String
    let systems: [SystemStatus]
    @State private var time: Date
    @State private var kind: RepeatKind
    @State private var days: Set<Int>
    @State private var onceDate: Date
    let onSave: (Alarm) -> Void

    init(alarm: Alarm, systems: [SystemStatus], onSave: @escaping (Alarm) -> Void) {
        self.onSave = onSave
        self.systems = systems
        _alarm = State(initialValue: alarm)
        _mode = State(initialValue: alarm.trigger == nil ? .time : .trigger)
        let system = alarm.trigger?.system ?? TriggerEvent.systems[0]
        _triggerSystem = State(initialValue: system)
        _triggerEvent = State(initialValue: alarm.trigger?.event ?? TriggerEvent.events(for: system)[0].id)
        let cal = Calendar.current
        _time = State(initialValue: cal.date(bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: Date()) ?? Date())
        switch alarm.repeatRule {
        case .daily: _kind = State(initialValue: .daily); _days = State(initialValue: []); _onceDate = State(initialValue: Date())
        case .weekdays: _kind = State(initialValue: .weekdays); _days = State(initialValue: []); _onceDate = State(initialValue: Date())
        case .days(let d): _kind = State(initialValue: .days); _days = State(initialValue: Set(d)); _onceDate = State(initialValue: Date())
        case .once(let day):
            _kind = State(initialValue: .once); _days = State(initialValue: [])
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            _onceDate = State(initialValue: f.date(from: day) ?? Date())
        }
    }

    private var isDailyReport: Bool { alarm.prompt == Alarm.dailyReportPrompt }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(alarm.title.isEmpty && alarm.prompt.isEmpty ? "알림 추가" : "알림 수정").font(.headline)

            Form {
                Section("언제") {
                    HStack(spacing: 6) {
                        Picker("방식", selection: $mode) {
                            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        TriggerHelpIcon()
                    }
                    if mode == .trigger {
                        Picker("시스템", selection: $triggerSystem) {
                            ForEach(TriggerEvent.systems, id: \.self) { system in
                                Text(systemLabel(system)).tag(system)
                            }
                        }
                        .onChange(of: triggerSystem) {
                            triggerEvent = TriggerEvent.events(for: triggerSystem)[0].id
                            autoTitle()
                        }
                        Picker("이벤트", selection: $triggerEvent) {
                            ForEach(TriggerEvent.events(for: triggerSystem)) { Text($0.name).tag($0.id) }
                        }
                        .onChange(of: triggerEvent) { autoTitle() }
                        if systems.first(where: { $0.system == triggerSystem })?.status != .connected {
                            Text("\(SystemNames.name(triggerSystem)) 이(가) 연결돼 있지 않아요. 연결 메뉴에서 먼저 연결해 주세요.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                if mode == .time {
                Section("시각과 반복") {
                    DatePicker("시각", selection: $time, displayedComponents: .hourAndMinute)
                    Picker("반복", selection: $kind) {
                        ForEach(RepeatKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if kind == .days {
                        HStack(spacing: 4) {
                            ForEach(Array(zip(1...7, ["일", "월", "화", "수", "목", "금", "토"])), id: \.0) { day, name in
                                Toggle(name, isOn: Binding(
                                    get: { days.contains(day) },
                                    set: { on in if on { days.insert(day) } else { days.remove(day) } }
                                ))
                                .toggleStyle(.button)
                            }
                        }
                    }
                    if kind == .once {
                        DatePicker("날짜", selection: $onceDate, displayedComponents: .date)
                    }
                }
                }
                Section("무엇을") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("제목").font(.caption).foregroundStyle(.secondary)
                        TextField("", text: $alarm.title, prompt: Text("알림에 보일 이름. 예: 근무일정 확인"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                    }
                    if isDailyReport {
                        Text("내 미완료 Jira 를 정리해서 보고 (기본 보고 문구)").foregroundStyle(.secondary)
                        Button("직접 쓰기로 바꾸기") { alarm.prompt = "" }.buttonStyle(.link)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("내용").font(.caption).foregroundStyle(.secondary)
                            TextField("", text: $alarm.prompt,
                                      prompt: Text(mode == .trigger ? "비워두면 알림만. 예: 이 PR 변경 내용 요약해줘"
                                                                    : "비워두면 알림만. 예: 이번 주 내 근무일정 알려줘"),
                                      axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .labelsHidden()
                                .lineLimit(3...6)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("저장") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(alarm.title.trimmingCharacters(in: .whitespaces).isEmpty
                              || (mode == .time && kind == .days && days.isEmpty))
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { if alarm.title.isEmpty && mode == .trigger { autoTitle() } }
        .onChange(of: mode) { if mode == .trigger && alarm.title.isEmpty { autoTitle() } }
    }

    private func systemLabel(_ system: String) -> String {
        let connected = systems.first { $0.system == system }?.status == .connected
        return SystemNames.name(system) + (connected ? "" : " (연결 안 됨)")
    }

    /// 제목이 비었거나 예전에 자동으로 채운 이름이면 고른 이벤트로 다시 채운다.
    private func autoTitle() {
        let autoNames = TriggerEvent.all.map { "\(SystemNames.name($0.system)) · \($0.name)" }
        guard alarm.title.isEmpty || autoNames.contains(alarm.title) || alarm.title == "GitHub · 리뷰 요청" else { return }
        if let event = TriggerEvent.find(triggerEvent) {
            alarm.title = "\(SystemNames.name(event.system)) · \(event.name)"
        }
    }

    private func save() {
        if mode == .trigger {
            alarm.trigger = Trigger(system: triggerSystem, event: triggerEvent)
            if alarm.prompt == Alarm.dailyReportPrompt { alarm.prompt = "" }
            onSave(alarm)
            dismiss()
            return
        }
        alarm.trigger = nil
        let cal = Calendar.current
        alarm.hour = cal.component(.hour, from: time)
        alarm.minute = cal.component(.minute, from: time)
        switch kind {
        case .daily: alarm.repeatRule = .daily
        case .weekdays: alarm.repeatRule = .weekdays
        case .days: alarm.repeatRule = .days(days.sorted())
        case .once: alarm.repeatRule = .once(ReportSchedule.dayString(onceDate, calendar: cal)); alarm.enabled = true
        }
        // 시각이나 반복을 바꾸면 기록을 새로 잡는다 (오늘 시각이 이미 지났으면 다음부터).
        alarm.resetSchedule(now: Date(), calendar: cal)
        onSave(alarm)
        dismiss()
    }
}

enum SystemNames {
    static func name(_ id: String) -> String {
        ["github": "GitHub", "deploy": "Deploy", "jira": "Jira", "wiki": "Wiki", "hr": "HR"][id] ?? id
    }
}

/// 트리거 설명 아이콘. 마우스를 올리면 동작 방식을 알려 준다.
struct TriggerHelpIcon: View {
    var body: some View {
        Image(systemName: "questionmark.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .help("켜져 있는 동안 5분마다 확인해서, 새로 생긴 것만 알려 드려요. 처음 켤 때 이미 있던 건 알리지 않아요.")
    }
}
