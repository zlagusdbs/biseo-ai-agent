import KimBiseoCore
import SwiftUI

struct ConnectionsView: View {
    @ObservedObject var model: AppModel
    @State private var loginTarget: LoginTarget?
    @State private var githubHost: GitHubHost?
    @State private var resultMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("연결").font(.headline)
                Spacer()
                if model.isLoadingSystems { ProgressView().controlSize(.small) }
                Button { Task { await model.refreshSystems() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain)
            }
            .padding(12)

            Divider()

            List {
                ForEach(model.systems.filter { $0.status != .unavailable }) { system in
                    HStack {
                        Text(system.name).frame(width: 110, alignment: .leading)
                        statusLabel(system.status)
                        Spacer()
                        Button(system.status == .disconnected ? "연결" : "다시 연결") {
                            if system.auth == "gh" {
                                githubHost = GitHubHost(host: URL(string: system.baseUrl ?? "")?.host ?? "github.com")
                            } else {
                                loginTarget = LoginTarget(target: .system(system.system), title: system.name)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                // claude.ai 커넥터: 연결·해제는 claude.ai 설정에서 한다.
                HStack {
                    Text("Microsoft 365").frame(width: 110, alignment: .leading)
                    if let status = model.microsoft365 {
                        statusLabel(status == .connected ? .connected : .disconnected)
                    } else {
                        ProgressView().controlSize(.small)
                        Text("확인 중").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("설정 열기") { NSWorkspace.shared.open(ConnectorStatus.settingsURL) }
                        .help("claude.ai 커넥터 설정에서 Microsoft 365 를 연결·해제해요")
                }
                .padding(.vertical, 4)
                ForEach(model.systems.filter { $0.status == .unavailable }) { system in
                    HStack {
                        Text(system.name).frame(width: 110, alignment: .leading)
                        Spacer()
                        Text("준비 중").foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            if let error = model.connectionError {
                Text(error).foregroundStyle(.red).font(.caption).padding(.horizontal, 12)
            }
            if let resultMessage {
                Text(resultMessage).font(.callout).padding(.horizontal, 12).padding(.top, 6)
            }

            Divider().padding(.top, 8)
            Button {
                loginTarget = LoginTarget(target: .group("ad"), title: "사내 계정 일괄 연동")
            } label: {
                Text("일괄 연동").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .padding(12)
        }
        .task { await model.refreshSystems() }
        .sheet(item: $githubHost, onDismiss: { Task { await model.refreshSystems() } }) { host in
            GitHubLoginSheet(host: host.host, settings: model.settings)
        }
        .sheet(item: $loginTarget) { target in
            LoginSheet(title: target.title) { username, secret in
                let results = await model.connect(target.target, username: username, secret: secret)
                resultMessage = results
                    .filter { $0.status != "unavailable" }
                    .map { "\($0.system.isEmpty ? "" : "\($0.system): ")\($0.message)" }
                    .joined(separator: "\n")
                return results.allSatisfy { $0.status == "connected" || $0.status == "unavailable" }
            }
        }
    }

    @ViewBuilder
    private func statusLabel(_ status: SystemStatus.Status) -> some View {
        switch status {
        case .connected: Label("연결됨", systemImage: "circle.fill").foregroundStyle(.green)
        case .disconnected: Label("연결 안 됨", systemImage: "circle").foregroundStyle(.secondary)
        case .expired: Label("만료됨", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .unavailable: EmptyView()
        }
    }
}

struct LoginTarget: Identifiable {
    let target: ConnectTarget
    let title: String
    var id: String { title }
}

struct LoginSheet: View {
    let title: String
    let submit: (String, String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var secret = ""
    @State private var working = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Text("사내 계정(AD) 아이디와 비밀번호를 입력하세요. 비밀번호는 이 Mac 의 키체인에만 저장돼요.")
                .font(.caption).foregroundStyle(.secondary)
            RomanTextField(placeholder: "아이디", text: $username)
            RomanTextField(placeholder: "비밀번호", text: $secret, secure: true)
            if failed { Text("연결하지 못했어요. 아래 결과 메시지를 확인해 주세요.").font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                Button {
                    working = true
                    Task {
                        let ok = await submit(username, secret)
                        working = false
                        secret = ""
                        if ok { dismiss() } else { failed = true }
                    }
                } label: {
                    if working { ProgressView().controlSize(.small) } else { Text("연결") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(username.isEmpty || secret.isEmpty || working)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

struct GitHubHost: Identifiable {
    let host: String
    var id: String { host }
}

/// GitHub 로그인: 한 번용 코드를 보여 주고 브라우저에서 승인받는다 (GitHub CLI 로그인을 김비서가 대신 실행).
struct GitHubLoginSheet: View {
    let host: String
    let settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var login = GitHubLogin()
    @State private var code: String?
    @State private var result: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GitHub 연결 (\(host))").font(.headline)
            if let result {
                Label(result ? "연결됐어요." : "연결하지 못했어요. 다시 시도해 주세요.",
                      systemImage: result ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(result ? .green : .red)
            } else if let code {
                Text("브라우저가 열리면 아래 코드를 입력하고 승인해 주세요.").font(.callout)
                HStack {
                    Text(code).font(.title2.monospaced()).textSelection(.enabled)
                    Button("복사") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                    }
                }
            } else {
                HStack { ProgressView().controlSize(.small); Text("로그인 준비 중…") }
            }
            HStack {
                Spacer()
                Button(result == nil ? "취소" : "닫기") { login.cancel(); dismiss() }
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            login.start(host: host, settings: settings) { event in
                switch event {
                case .code(let value): code = value
                case .finished(let ok): result = ok
                }
            }
        }
    }
}
