import KimBiseoCore
import SwiftUI

struct AlarmsView: View {
    @ObservedObject var model: AppModel
    @State private var editing: Alarm?
    /// 펼친 그룹. 앱을 다시 켜도 기억한다 (AppStorage 는 Set 을 못 담아서 줄바꿈으로 이은 문자열).
    @AppStorage("alarmExpandedGroups") private var expandedGroups = ""
    @AppStorage("alarmUngroupedCollapsed") private var ungroupedCollapsed = false
    /// 삭제 확인
    @State private var deletingAlarm: Alarm?
    @State private var deletingGroup: String?
    /// 그룹 만들기·이름 바꾸기 (nil 이면 새 그룹)
    @State private var naming: GroupNaming?
    @State private var groupName = ""
    /// 끌고 있는 알림이 올라가 있는 그룹 ("" 은 그룹 없음)
    @State private var dropTarget: String?
    /// 상세를 펼친 알림
    @State private var openRows: Set<UUID> = []

    private struct GroupNaming: Identifiable {
        let old: String?
        var id: String { old ?? "" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("알림").font(.headline)
                Spacer()
                Button {
                    groupName = ""
                    naming = GroupNaming(old: nil)
                } label: { Label("그룹", systemImage: "folder.badge.plus") }
                    .help("새 그룹 만들기. 알림을 그룹으로 끌어다 놓으면 옮겨져요")
                Button {
                    editing = Alarm(title: "", prompt: "", hour: 9, minute: 0, repeatRule: .weekdays)
                } label: { Label("추가", systemImage: "plus") }
            }
            .padding(12)
            Divider()

            if model.alarms.isEmpty && model.alarmGroups.isEmpty {
                Text("등록된 알림이 없어요. [추가]로 만들어 보세요.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 40)
                Spacer()
            } else {
                let split = AlarmGroup.make(model.alarms, groups: model.alarmGroups)
                List {
                    ForEach(split.groups) { group in
                        groupView(group)
                    }
                    ungroupedView(split.ungrouped)
                }
            }
        }
        .task { if model.systems.isEmpty { await model.refreshSystems() } }
        .sheet(item: $editing) { alarm in
            AlarmEditor(alarm: alarm, systems: model.systems, groups: model.alarmGroups) { model.save($0) }
        }
        .alert("알림을 삭제할까요?", isPresented: Binding(get: { deletingAlarm != nil }, set: { if !$0 { deletingAlarm = nil } }),
               presenting: deletingAlarm) { alarm in
            Button("삭제", role: .destructive) { model.alarms.removeAll { $0.id == alarm.id } }
            Button("취소", role: .cancel) {}
        } message: { alarm in
            Text("\"\(alarm.title.isEmpty ? "(제목 없음)" : alarm.title)\" \(alarm.trigger == nil ? alarm.timeText + " " : "")알림을 지워요. 되돌릴 수 없어요.")
        }
        .alert("그룹을 삭제할까요?", isPresented: Binding(get: { deletingGroup != nil }, set: { if !$0 { deletingGroup = nil } }),
               presenting: deletingGroup) { name in
            Button("그룹 삭제", role: .destructive) { model.deleteGroup(name) }
            Button("취소", role: .cancel) {}
        } message: { name in
            Text("\"\(name)\" 그룹만 지워요. 안에 있던 알림은 지우지 않고 \"그룹 없음\"으로 옮겨요.")
        }
        .alert(naming?.old == nil ? "새 그룹" : "그룹 이름 바꾸기",
               isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } }), presenting: naming) { target in
            TextField("그룹 이름", text: $groupName)
            Button("저장") {
                if let old = target.old { model.renameGroup(old, to: groupName) } else { model.addGroup(groupName) }
            }
            .disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("취소", role: .cancel) {}
        }
    }
}

extension AlarmsView {
    /// 그룹 하나. 머리줄은 누르면 펼치기·접기만 하고, 이름 바꾸기·삭제·모두 켜기/끄기는 오른쪽 클릭 메뉴에 둔다.
    /// 머리줄에 알림을 끌어다 놓으면 이 그룹으로 옮긴다.
    @ViewBuilder
    private func groupView(_ group: AlarmGroup) -> some View {
        let expanded = contains(expandedGroups, group.name)
        Button { expandedGroups = toggled(expandedGroups, group.name) } label: {
            HStack(spacing: 6) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption2.weight(.semibold))
                    .frame(width: 10)
                Image(systemName: "folder").font(.caption).foregroundStyle(Color.accentColor)
                Text(group.name).font(.callout.weight(.semibold)).lineLimit(1)
                Text("\(group.alarms.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if group.alarms.contains(where: { model.alarmRuns[$0.id] == .running }) {
                    ProgressView().controlSize(.mini).help("이 그룹에서 실행 중인 알림이 있어요")
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(expanded ? "접기 · 오른쪽 클릭: 이름 바꾸기, 삭제" : "펼치기 · 오른쪽 클릭: 이름 바꾸기, 삭제")
        .contextMenu {
            Button("모두 켜기") { for alarm in group.alarms { setEnabled(alarm.id, true) } }
            Button("모두 끄기") { for alarm in group.alarms { setEnabled(alarm.id, false) } }
            Divider()
            Button("이름 바꾸기") { groupName = group.name; naming = GroupNaming(old: group.name) }
            Button("그룹 삭제", role: .destructive) { deletingGroup = group.name }
        }
        .dropTarget(isOn: dropTarget == group.name)
        .dropDestination(for: String.self) { ids, _ in drop(ids, into: group.name) } isTargeted: { on in
            dropTarget = on ? group.name : (dropTarget == group.name ? nil : dropTarget)
        }
        if expanded {
            if group.alarms.isEmpty {
                Text("비어 있어요. 알림을 끌어다 놓으세요.").font(.caption).foregroundStyle(.secondary).padding(.leading, 26)
            }
            ForEach(group.alarms) { alarm in
                row(alarm).padding(.leading, 16)
                    .dropDestination(for: String.self) { ids, _ in drop(ids, into: group.name) }
            }
        }
    }

    /// 그룹에 넣지 않은 알림. 머리줄에 끌어다 놓으면 그룹에서 뺀다.
    @ViewBuilder
    private func ungroupedView(_ alarms: [Alarm]) -> some View {
        if !alarms.isEmpty || !model.alarmGroups.isEmpty {
            Section {
                if !ungroupedCollapsed {
                    ForEach(alarms) { alarm in
                        row(alarm).dropDestination(for: String.self) { ids, _ in drop(ids, into: nil) }
                    }
                }
            } header: {
                Button { ungroupedCollapsed.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: ungroupedCollapsed ? "chevron.right" : "chevron.down").font(.caption2.weight(.semibold))
                            .frame(width: 10)
                        Text("그룹 없음").font(.caption)
                        Text("\(alarms.count)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .dropTarget(isOn: dropTarget == "")
                .dropDestination(for: String.self) { ids, _ in drop(ids, into: nil) } isTargeted: { on in
                    dropTarget = on ? "" : (dropTarget == "" ? nil : dropTarget)
                }
            }
        }
    }

    /// 알림 한 개. 평소엔 켜기 스위치와 제목 한 줄만 보이고, 아래 화살표를 누르면 상세와 버튼이 펼쳐진다.
    /// 끌어서 다른 그룹으로 옮길 수 있다.
    private func row(_ alarm: Alarm) -> some View {
        let open = openRows.contains(alarm.id)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(get: { alarm.enabled }, set: { setEnabled(alarm.id, $0) }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                if alarm.trigger != nil {
                    Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(Color.orange).help("트리거")
                }
                Text(alarm.title.isEmpty ? "(제목 없음)" : alarm.title).font(.callout).lineLimit(1)
                    .foregroundStyle(alarm.enabled ? Color.primary : Color.secondary)
                Spacer()
                HStack(spacing: 10) {
                    if model.alarmRuns[alarm.id] == .running {
                        ProgressView().controlSize(.mini)
                            .help(alarm.trigger == nil ? "실행 중이에요. 끝나면 알림 창에 결과가 떠요" : "새로 생긴 게 있는지 보고 있어요")
                    } else {
                        Button { model.runAlarmNow(alarm) } label: { Image(systemName: "play.fill") }
                            .help(alarm.trigger == nil ? "지금 실행" : "지금 확인")
                    }
                    Button { editing = alarm } label: { Image(systemName: "pencil") }.help("수정")
                    Button(role: .destructive) { deletingAlarm = alarm } label: { Image(systemName: "trash") }
                        .foregroundStyle(.red).help("삭제")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                Button {
                    if open { openRows.remove(alarm.id) } else { openRows.insert(alarm.id) }
                } label: {
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary).frame(width: 18, height: 16).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(open ? "접기" : "자세히")
            }
            if case .done(let message, let failed) = model.alarmRuns[alarm.id] {
                Label(message, systemImage: failed ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .font(.caption2).foregroundStyle(failed ? Color.red : Color.green)
                    .padding(.leading, 40)
            }
            if open {
                details(alarm).padding(.leading, 40)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .draggable(alarm.id.uuidString) {
            Label(alarm.title.isEmpty ? "(제목 없음)" : alarm.title, systemImage: "bell")
                .padding(6).background(.background, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    /// 펼쳤을 때 보이는 상세: 언제, 무엇을, 받을 곳, 마지막 실행. (실행·수정·삭제 버튼은 제목 줄에 있다)
    private func details(_ alarm: Alarm) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let trigger = alarm.trigger {
                HStack(spacing: 4) {
                    Text("트리거 · \(SystemNames.name(trigger.system)) · \(TriggerEvent.find(trigger.event)?.name ?? trigger.event) · \(trigger.interval)분마다")
                    TriggerHelpIcon()
                }
            } else {
                Text("\(alarm.timeText) · \(alarm.repeatRule.description)").monospacedDigit()
            }
            Text(alarm.prompt == Alarm.dailyReportPrompt ? "내 미완료 Jira 를 정리해서 보고"
                 : alarm.prompt.isEmpty ? (alarm.trigger == nil ? "시각에 알림만" : "생기면 바로 알림") : alarm.prompt)
                .foregroundStyle(.secondary).lineLimit(3)
            HStack(spacing: 8) {
                DeliveryBadge(on: alarm.toMac, symbol: "macwindow", text: "Mac 알림")
                DeliveryBadge(on: alarm.toPanel, symbol: "rectangle.bottomhalf.inset.filled", text: "미리 알림 창")
                if let last = alarm.lastRunDay {
                    Text("마지막 실행 \(last)").foregroundStyle(.tertiary)
                }
            }
            .font(.caption2)
        }
        .font(.caption)
    }

    private func drop(_ ids: [String], into group: String?) -> Bool {
        let uuids = ids.compactMap(UUID.init(uuidString:))
        for id in uuids { model.move(alarmID: id, to: group) }
        dropTarget = nil
        return !uuids.isEmpty
    }

    private func setEnabled(_ id: UUID, _ on: Bool) {
        if let i = model.alarms.firstIndex(where: { $0.id == id }) { model.alarms[i].enabled = on }
    }

    private func contains(_ stored: String, _ key: String) -> Bool {
        stored.split(separator: "\n").contains { $0 == key }
    }

    private func toggled(_ stored: String, _ key: String) -> String {
        var keys = stored.split(separator: "\n").map(String.init)
        if let i = keys.firstIndex(of: key) { keys.remove(at: i) } else { keys.append(key) }
        return keys.joined(separator: "\n")
    }
}

private extension View {
    /// 끌어다 놓을 곳 위에 올라가 있으면 파란 테두리로 표시한다.
    func dropTarget(isOn: Bool) -> some View {
        background(RoundedRectangle(cornerRadius: 6).fill(isOn ? Color.accentColor.opacity(0.12) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(isOn ? Color.accentColor : .clear, lineWidth: 1.5))
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
    @State private var triggerInterval: Int
    let systems: [SystemStatus]
    @State private var time: Date
    @State private var kind: RepeatKind
    @State private var days: Set<Int>
    @State private var onceDate: Date
    let groups: [String]
    let onSave: (Alarm) -> Void

    init(alarm: Alarm, systems: [SystemStatus], groups: [String] = [], onSave: @escaping (Alarm) -> Void) {
        self.onSave = onSave
        self.groups = groups
        self.systems = systems
        _alarm = State(initialValue: alarm)
        _mode = State(initialValue: alarm.trigger == nil ? .time : .trigger)
        let system = alarm.trigger?.system ?? TriggerEvent.systems[0]
        _triggerSystem = State(initialValue: system)
        _triggerEvent = State(initialValue: alarm.trigger?.event ?? TriggerEvent.events(for: system)[0].id)
        _triggerInterval = State(initialValue: alarm.trigger?.interval ?? Trigger.defaultInterval)
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
                        Picker("확인 주기", selection: $triggerInterval) {
                            ForEach(Trigger.intervals, id: \.self) { Text("\($0)분마다").tag($0) }
                        }
                        if systems.first(where: { $0.system == triggerSystem })?.status != .connected {
                            Text("\(SystemNames.name(triggerSystem)) 이(가) 연결돼 있지 않아요. 연결 메뉴에서 먼저 연결해 주세요.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                .grayCard()
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
                .grayCard()
                }
                Section("받을 곳") {
                    HStack(spacing: 16) {
                        Toggle("Mac 알림", isOn: Binding(get: { alarm.toMac }, set: { alarm.notifyMac = $0 }))
                            .help("화면 오른쪽 위에 잠깐 떴다가 알림 센터에 쌓이는 macOS 알림")
                        Toggle("미리 알림 창", isOn: Binding(get: { alarm.toPanel }, set: { alarm.notifyPanel = $0 }))
                            .help("화면 오른쪽 아래에 [확인]을 누를 때까지 남아 있는 김비서 카드")
                    }
                    .toggleStyle(.checkbox)
                    if !alarm.toMac && !alarm.toPanel {
                        Label("둘 다 끄면 알림이 오지 않아요\(mode == .time ? " (결과는 채팅창에만 남아요)" : "")",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                .grayCard()
                Section("무엇을") {
                    if !groups.isEmpty {
                        Picker("그룹", selection: $alarm.group) {
                            Text("그룹 없음").tag(String?.none)
                            ForEach(groups, id: \.self) { Text($0).tag(String?.some($0)) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("제목").font(.caption).foregroundStyle(.secondary)
                        TextField("", text: $alarm.title, prompt: Text("알림에 보일 이름. 예: 근무일정 확인"))
                            .whiteField()
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
                                .whiteField()
                                .labelsHidden()
                                .lineLimit(3...6)
                        }
                    }
                }
                .grayCard()
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
            alarm.trigger = Trigger(system: triggerSystem, event: triggerEvent, intervalMinutes: triggerInterval)
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

/// 트리거 설명 아이콘.
struct TriggerHelpIcon: View {
    var body: some View {
        HelpIcon(text: "켜져 있는 동안 정한 주기(기본 5분)마다 확인해서, 새로 생긴 것만 알려 드려요.\n처음 켤 때 이미 있던 건 알리지 않아요. 바로 보고 싶으면 ▶(지금 확인)을 누르세요.\n내용을 비워 두면 바로 알리고, 내용을 적으면 김비서가 그 일을 한 뒤 결과를 알려요(조금 느림).")
    }
}

/// ? 아이콘. 마우스를 올리거나 누르면 말풍선으로 설명한다.
/// (시트·패널 안에서는 macOS 기본 툴팁(.help)이 잘 안 떠서 말풍선을 쓴다)
struct HelpIcon: View {
    let text: String
    @State private var showing = false

    var body: some View {
        Image(systemName: "questionmark.circle")
            .font(.caption)
            .foregroundStyle(showing ? Color.accentColor : Color.secondary)
            .contentShape(Rectangle())
            .onHover { showing = $0 }
            .onTapGesture { showing.toggle() }
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                Text(text)
                    .font(.callout)
                    .padding(10)
                    .frame(width: 280, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
    }
}

/// 알림 목록에서 받을 곳 표시. 꺼진 곳은 흐리게 줄을 긋는다.
private struct DeliveryBadge: View {
    let on: Bool
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .foregroundStyle(on ? Color.secondary : Color.secondary.opacity(0.4))
            .strikethrough(!on)
            .help(on ? "\(text)으로 받아요" : "\(text)으로는 받지 않아요")
    }
}
