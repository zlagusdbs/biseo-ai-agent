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


/// 김비서 폴더의 md: root(CLAUDE.md, 고치기만) · rules(질문마다 모두 읽음) · skills(주제가 나올 때만 읽음).
private struct RulesSection: View {
    @State private var files: [Rules.File] = []
    @State private var deleting: Rules.File?
    @State private var creating: Rules.Kind?
    @State private var newName = ""

    var body: some View {
        Group {
            Section {
                ForEach(files.filter { $0.kind == .root }) { file in
                    fileRow(file, deletable: false)
                }
                if !files.contains(where: { $0.kind == .root }) {
                    Text("CLAUDE.md 가 없어요. 폴더를 열어 만들어 주세요.").foregroundStyle(.secondary)
                }
            } header: {
                header("root", help: "김비서 전체에 늘 적용하는 기본 지시예요 (말투, 답하는 방식 등).\n김비서를 실행할 때 Claude Code 가 김비서 폴더의 CLAUDE.md 를 직접 읽기 때문에, 지우면 기본 지시가 사라져요. 그래서 고치기만 하고 지울 수는 없어요.")
            }
            Section {
                ForEach(files.filter { $0.kind == .rule }) { file in fileRow(file, deletable: true) }
                Button("새 규칙") { newName = ""; creating = .rule }
            } header: {
                header("rules", help: "질문할 때마다 모든 파일을 통째로 읽어요. 길수록 질문마다 비용이 늘고 답이 느려지니, 늘 지켜야 할 것만 짧게 적고 파일당 200줄을 넘기지 마세요.\n채팅에서 \"기억해\" 하고 [기억하기]를 누르면 rules/memory.md 에 쌓여요.")
            }
            Section {
                ForEach(files.filter { $0.kind == .skill }) { file in fileRow(file, deletable: true) }
                Button("새 스킬") { newName = ""; creating = .skill }
            } header: {
                header("skills", help: "주제별 안내서예요. 평소엔 한 줄 설명만 보내고, 질문에 그 주제의 키워드가 나오면 그때 본문을 읽어요.\n예: Jira 이야기가 나오면 skills/jira.md 를 읽어요. 키워드가 없어도 필요하면 김비서가 직접 찾아 읽어요.\n파일 맨 위에 description(한 줄 설명)과 keywords(쉼표로 구분)를 적어 주세요.")
            } footer: {
                HStack {
                    Text("고친 내용은 다음 질문부터 바로 적용돼요.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("폴더 열기") { NSWorkspace.shared.open(Rules.homeDir) }.buttonStyle(.link)
                    Button { reload() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).help("새로고침")
                }
            }
        }
        .task { reload() }
        .alert("파일을 삭제할까요?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
               presenting: deleting) { file in
            Button("삭제", role: .destructive) { try? Rules.delete(file); reload() }
            Button("취소", role: .cancel) {}
        } message: { file in
            Text("\(file.name) 을(를) 지워요. 되돌릴 수 없어요.")
        }
        .alert(creating == .skill ? "새 스킬" : "새 규칙", isPresented: Binding(get: { creating != nil }, set: { if !$0 { creating = nil } })) {
            TextField("파일 이름. 예: wiki", text: $newName)
            Button("만들기") {
                if let kind = creating, let url = try? Rules.create(newName, kind: kind) { NSWorkspace.shared.open(url); reload() }
            }
            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("취소", role: .cancel) {}
        } message: {
            Text(creating == .skill ? "skills/ 폴더에 md 파일을 만들고 열어요." : "rules/ 폴더에 md 파일을 만들고 열어요.")
        }
    }

    private func header(_ title: String, help: String) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.body.monospaced().weight(.semibold))
            HelpIcon(text: help)
        }
    }

    private func fileRow(_ file: Rules.File, deletable: Bool) -> some View {
        HStack {
            Image(systemName: "doc.text").foregroundStyle(.secondary)
            Text(file.name).font(.body.monospaced())
            if file.kind == .rule {
                let lines = file.lineCount
                Text(lines > Rules.ruleLineLimit ? "\(lines)줄 · 200줄 넘음" : "\(lines)줄")
                    .font(.caption).foregroundStyle(lines > Rules.ruleLineLimit ? Color.orange : Color.secondary)
            }
            Spacer()
            Button("열기") { NSWorkspace.shared.open(file.url) }
            if deletable {
                Button(role: .destructive) { deleting = file } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("삭제")
            }
        }
    }

    private func reload() { files = Rules.files() }
}
