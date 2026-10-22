import AppKit
import KimBiseoCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("이름") {
                TextField("주인 이름", text: $model.settings.ownerName, prompt: Text("김비서가 부를 이름"))
            }
            MemorySection()
            RulesSection(settings: model.settings)
            Section("단축키") {
                HotkeyRecorder(hotkey: $model.settings.hotkey)
            }
            ClaudeAccountSection(model: model)
            JiraDefaultsSection(defaults: $model.jiraDefaults)
            Section("경로") {
                TextField("김비서 저장소", text: $model.settings.repoDir)
                TextField("claude", text: $model.settings.claudePath)
                TextField("uv", text: $model.settings.uvPath)
            }
            Section {
                Button("김비서 종료") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
    }
}

/// [변경] 을 누르고 원하는 키 조합을 누르면 바로 바뀐다. Esc 는 취소.
private struct HotkeyRecorder: View {
    @Binding var hotkey: Hotkey
    @State private var recording = false
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("채팅창 열기·닫기")
                Spacer()
                Text(recording ? "키 조합을 누르세요…" : hotkey.display)
                    .font(.body.monospaced())
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(recording ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 6))
                Button(recording ? "취소" : "변경") { recording ? stop() : start() }
                if hotkey != .default && !recording {
                    Button("기본값") { hotkey = .default; message = nil }
                }
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        message = nil
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }   // Esc
            let flags = event.modifierFlags
            var mods: UInt32 = 0
            if flags.contains(.command) { mods |= Hotkey.command }
            if flags.contains(.shift) { mods |= Hotkey.shift }
            if flags.contains(.option) { mods |= Hotkey.option }
            if flags.contains(.control) { mods |= Hotkey.control }
            let candidate = Hotkey(keyCode: UInt32(event.keyCode), modifiers: mods)
            if candidate.isValid {
                hotkey = candidate
                message = "\(candidate.display) 로 바꿨어요. 다른 앱과 겹치면 그 앱의 단축키가 먼저 동작할 수 있어요."
                stop()
            } else {
                message = "⌘, ⌃, ⌥ 중 하나 이상을 같이 눌러 주세요."
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Jira 등록 기본값. 처음 김비서에게 등록을 시키면 물어보고 저장한다. 여기서 직접 고치거나 지울 수 있다.
private struct JiraDefaultsSection: View {
    @Binding var defaults: JiraDefaults?

    var body: some View {
        Section {
            if let value = defaults {
                let binding = Binding(get: { value }, set: { defaults = $0 })
                TextField("프로젝트 키", text: binding.project)
                TextField("개발 일 유형", text: binding.devType)
                TextField("일반 업무 유형", text: binding.taskType)
                TextField("Original Estimate", text: binding.originalEstimate)
                Picker("Target start", selection: binding.targetStart) {
                    Text("등록하는 날").tag(JiraDefaults.StartRule.today)
                    Text("비움").tag(JiraDefaults.StartRule.none)
                }
                Picker("Target end", selection: binding.targetEnd) {
                    Text("그해 12월 31일").tag(JiraDefaults.EndRule.yearEnd)
                    Text("비움").tag(JiraDefaults.EndRule.none)
                }
                TextField("Epic Link", text: binding.epicLink, prompt: Text("비우면 안 넣음"))
                Button("기본값 지우기", role: .destructive) { defaults = nil }
                    .help("지우면 다음 등록 때 김비서가 다시 물어봐요")
            } else {
                Text("아직 없어요. 김비서에게 처음 Jira 등록을 시키면 물어보고 저장해요.")
                    .foregroundStyle(.secondary)
                Button("직접 정하기") { defaults = JiraDefaults(project: "") }
            }
        } header: {
            Text("Jira 등록 기본값")
        } footer: {
            Text("이 Mac 에만 저장돼요. 담당자는 항상 연결된 Jira 계정 본인이에요.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// 김비서가 쓰는 Claude 계정. 전용 로그인을 켜면 터미널 Claude Code 와 다른 계정(예: 팀 플랜)으로 쓸 수 있다.
private struct ClaudeAccountSection: View {
    @ObservedObject var model: AppModel
    @State private var account: ClaudeAccount?
    @State private var loading = false

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { model.settings.separateClaudeLogin }, set: { on in
                model.settings.separateClaudeLogin = on
                model.chat.forgetSession()
                Task { await refresh() }
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("김비서 전용 로그인 쓰기")
                    Text(model.settings.separateClaudeLogin
                         ? "김비서만 따로 로그인해요. 터미널 Claude Code 로그인은 그대로예요."
                         : "지금은 터미널 Claude Code 와 같은 로그인을 같이 써요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("연결된 계정")
                Spacer()
                if loading {
                    ProgressView().controlSize(.small)
                } else {
                    Text(account?.display ?? "claude 를 찾지 못했어요").foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            if model.settings.separateClaudeLogin {
                HStack {
                    Button(account?.loggedIn == true ? "다른 계정으로 로그인" : "로그인") {
                        Task {
                            if account?.loggedIn == true { await ClaudeLogin.logout(settings: model.settings) }
                            model.selected = .chat
                            model.chat.startLogin(retry: nil)
                        }
                    }
                    if account?.loggedIn == true {
                        Button("로그아웃") { Task { await ClaudeLogin.logout(settings: model.settings); await refresh() } }
                    }
                }
            }
        } header: {
            Text("김비서 Claude 계정")
        } footer: {
            Text("로그인할 때 브라우저에서 쓸 조직(회사 Enterprise, 팀 플랜 등)을 고를 수 있어요. 사내 데이터를 어느 조직으로 보내도 되는지는 회사 기준을 따라 주세요. Microsoft 365 커넥터는 로그인한 계정의 claude.ai 설정에서 따로 연결해야 해요.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task { await refresh() }
        .onChange(of: model.chat.loginState) { if model.chat.loginState == .idle { Task { await refresh() } } }
    }

    private func refresh() async {
        loading = true
        account = await ClaudeLogin.account(settings: model.settings)
        loading = false
    }
}

/// 김비서 규칙 md 목록. 질문할 때마다 공통 → 팀 → 나 순서로 읽는다.
private struct RulesSection: View {
    let settings: AppSettings
    @State private var files: [Rules.File] = []

    var body: some View {
        Section {
            if files.isEmpty {
                Text("규칙 파일이 없어요.").foregroundStyle(.secondary)
            }
            ForEach(files) { file in
                HStack {
                    Text(file.layer.rawValue).font(.caption.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                    Text(file.name)
                    Spacer()
                    Button("열기") { NSWorkspace.shared.open(file.url) }
                }
            }
            HStack {
                Button("새 내 규칙") {
                    if let url = try? Rules.append("여기에 규칙을 한 줄씩 적어요", to: "my-rules") {
                        NSWorkspace.shared.open(url)
                        reload()
                    }
                }
                Button("내 규칙 폴더") {
                    try? FileManager.default.createDirectory(at: Rules.myDir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(Rules.myDir)
                }
                Button("팀 규칙 폴더") { NSWorkspace.shared.open(Rules.sharedDir(settings: settings)) }
                Spacer()
                Button { reload() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
            }
        } header: {
            Text("규칙")
        } footer: {
            Text("공통(저장소, 공개) → 팀(*.local.md, Git 에 안 올라감) → 나(이 Mac) 순서로 읽고, 서로 다르면 뒤의 규칙을 따라요. 고친 내용은 다음 질문부터 바로 적용돼요.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task { reload() }
    }

    private func reload() { files = Rules.files(settings: settings) }
}

/// 김비서 기억 (memory.md). 채팅에서 "기억해" 하고 [기억하기]를 누르면 쌓이고, 여기서 지울 수 있다.
private struct MemorySection: View {
    @State private var items: [String] = []
    @State private var draft = ""

    var body: some View {
        Section {
            if items.isEmpty {
                Text("아직 기억한 게 없어요. 채팅에서 \"내 팀은 가격팀이야, 기억해\" 처럼 말해 보세요.")
                    .foregroundStyle(.secondary)
            }
            ForEach(items, id: \.self) { item in
                HStack {
                    Text(item)
                    Spacer()
                    Button(role: .destructive) {
                        try? Memory.forget(item)
                        reload()
                    } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless).help("잊기")
                }
            }
            HStack {
                TextField("", text: $draft, prompt: Text("직접 추가. 예: 매주 화요일 10시 팀 회의"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("추가", action: add).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("기억")
        } footer: {
            Text("이 Mac 의 memory.md 에 저장돼요. 새 대화를 시작해도 김비서가 알고 있어요.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task { reload() }
    }

    private func add() {
        try? Memory.add(draft)
        draft = ""
        reload()
    }

    private func reload() { items = Memory.items() }
}
