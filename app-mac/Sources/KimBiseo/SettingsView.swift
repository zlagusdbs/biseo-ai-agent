import AppKit
import KimBiseoCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("단축키") {
                HotkeyRecorder(hotkey: $model.settings.hotkey)
            }
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
