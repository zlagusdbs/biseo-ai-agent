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
            RulesSection()
            Section("단축키") {
                HotkeyRecorder(hotkey: $model.settings.hotkey)
            }
            ClaudeAccountSection(model: model)
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

/// 김비서가 쓰는 Claude 계정. 전용 로그인을 켜면 터미널 Claude Code 와 다른 계정(예: 팀 플랜)으로 쓸 수 있다.
private struct ClaudeAccountSection: View {
    @ObservedObject var model: AppModel
    @State private var account: ClaudeAccount?
    @State private var loading = false

    var body: some View {
        Section {
            HStack {
                Text("연결된 계정")
                Spacer()
                if loading {
                    ProgressView().controlSize(.small)
                } else {
                    Text(account?.display ?? "claude 를 찾지 못했어요").foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            HStack {
                Button(account?.loggedIn == true ? "다른 계정으로 로그인" : "로그인") {
                    Task {
                        if account?.loggedIn == true { await ClaudeLogin.logout(settings: model.settings) }
                        model.chat.forgetSession()
                        model.selected = .chat
                        model.chat.startLogin(retry: nil)
                    }
                }
                if account?.loggedIn == true {
                    Button("로그아웃") { Task { await ClaudeLogin.logout(settings: model.settings); await refresh() } }
                }
            }
        } header: {
            Text("김비서 Claude 계정")
        } footer: {
            Text("김비서는 터미널 Claude Code 와 따로 로그인해요. 로그인할 때 브라우저에서 쓸 조직(팀 플랜 등)을 고를 수 있어요. 사내 데이터를 어느 조직으로 보내도 되는지는 회사 기준을 따라 주세요. Microsoft 365 커넥터는 로그인한 계정의 claude.ai 설정에서 따로 연결해야 해요.")
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


/// 김비서 폴더의 CLAUDE.md 와 rules/*.md. 열기·삭제, 새 규칙 만들기.
private struct RulesSection: View {
    @State private var files: [Rules.File] = []
    @State private var deleting: Rules.File?
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        Section {
            if files.isEmpty {
                Text("규칙 파일이 없어요. [새 규칙]으로 만들어 보세요.").foregroundStyle(.secondary)
            }
            ForEach(files) { file in
                HStack {
                    Image(systemName: "doc.text").foregroundStyle(.secondary)
                    Text(file.name).font(.body.monospaced())
                    Spacer()
                    Button("열기") { NSWorkspace.shared.open(file.url) }
                    Button(role: .destructive) { deleting = file } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless).help("삭제")
                }
            }
            HStack {
                Button("새 규칙") { newName = ""; naming = true }
                Button("폴더 열기") {
                    try? FileManager.default.createDirectory(at: Rules.myDir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(Rules.homeDir)
                }
                Spacer()
                Button { reload() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).help("새로고침")
            }
        } header: {
            Text("규칙")
        } footer: {
            Text("CLAUDE.md 는 전체 지시, rules/ 는 주제별 규칙이에요 (기억은 rules/memory.md). 고친 내용은 다음 질문부터 바로 적용돼요.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task { reload() }
        .alert("규칙 파일을 삭제할까요?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
               presenting: deleting) { file in
            Button("삭제", role: .destructive) { try? Rules.delete(file); reload() }
            Button("취소", role: .cancel) {}
        } message: { file in
            Text("\(file.name) 을(를) 지워요. 되돌릴 수 없어요.")
        }
        .alert("새 규칙", isPresented: $naming) {
            TextField("파일 이름. 예: wiki", text: $newName)
            Button("만들기") {
                if let url = try? Rules.create(newName) { NSWorkspace.shared.open(url); reload() }
            }
            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("취소", role: .cancel) {}
        } message: {
            Text("rules/ 폴더에 md 파일을 만들고 열어요.")
        }
    }

    private func reload() { files = Rules.files() }
}
