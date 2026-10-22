import Foundation

/// `claude auth login` 을 대신 실행한다. 브라우저를 열고, 브라우저에 나온 코드를 받아 표준 입력으로 넘긴다.
/// 코드는 화면·파일에 남기지 않는다.
public final class ClaudeLogin: @unchecked Sendable {
    public enum Event: Equatable {
        case browserOpened      // 브라우저를 띄웠다
        case needsCode          // 브라우저에 나온 코드를 붙여넣어야 한다
        case finished(Bool)     // 로그인 성공 여부
    }

    private var process: Process?
    private var input: FileHandle?
    private var buffer = ""
    private var askedCode = false
    private var cancelled = false

    public init() {}

    public static func isLoggedIn(settings: AppSettings) async -> Bool {
        await account(settings: settings)?.loggedIn ?? false
    }

    /// 김비서가 지금 쓰는 Claude 계정 (`claude auth status`). claude 를 못 찾으면 nil.
    public static func account(settings: AppSettings) async -> ClaudeAccount? {
        guard FileManager.default.isExecutableFile(atPath: settings.claudePath),
              let out = try? await ProcessRunner().run(executable: settings.claudePath, arguments: ["auth", "status"],
                                                       environment: AppPaths.processEnvironment(settings: settings),
                                                       timeout: 20)
        else { return nil }
        return ClaudeAccount.parse(out.stdout)
    }

    /// 김비서 전용 로그인에서 로그아웃 (터미널 Claude Code 로그인은 그대로).
    public static func logout(settings: AppSettings) async {
        _ = try? await ProcessRunner().run(executable: settings.claudePath, arguments: ["auth", "logout"],
                                           environment: AppPaths.processEnvironment(settings: settings), timeout: 20)
    }

    /// 로그인 시작. onEvent 는 메인 스레드에서 불린다.
    public func start(settings: AppSettings, onEvent: @escaping (Event) -> Void) {
        cancel()
        cancelled = false
        buffer = ""
        askedCode = false
        let process = Process()
        process.executableURL = URL(fileURLWithPath: settings.claudePath)
        process.arguments = ["auth", "login"]
        process.environment = AppPaths.processEnvironment(settings: settings)
        let out = Pipe(), inPipe = Pipe()
        process.standardOutput = out
        process.standardError = out
        process.standardInput = inPipe
        input = inPipe.fileHandleForWriting

        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let chunk = String(decoding: handle.availableData, as: UTF8.self)
            guard !chunk.isEmpty else { return }
            self.buffer += chunk
            if self.buffer.contains("Opening browser") || self.buffer.contains("visit:") {
                DispatchQueue.main.async { onEvent(.browserOpened) }
            }
            if !self.askedCode, self.buffer.localizedCaseInsensitiveContains("paste code") {
                self.askedCode = true
                DispatchQueue.main.async { onEvent(.needsCode) }
            }
        }
        process.terminationHandler = { [weak self] _ in
            out.fileHandleForReading.readabilityHandler = nil
            self?.input = nil
            guard self?.cancelled == false else { return }
            Task {
                let ok = await Self.isLoggedIn(settings: settings)
                DispatchQueue.main.async { onEvent(.finished(ok)) }
            }
        }
        do {
            try process.run()
            self.process = process
        } catch {
            onEvent(.finished(false))
        }
    }

    public func submit(code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let input else { return }
        input.write(Data((trimmed + "\n").utf8))
    }

    public func cancel() {
        cancelled = true
        if let process, process.isRunning { process.terminate() }
        process = nil
        input = nil
    }
}

/// `claude auth status` 결과.
public struct ClaudeAccount: Equatable {
    public let loggedIn: Bool
    public let email: String
    public let orgName: String
    public let plan: String       // enterprise, team, max, pro …

    public init(loggedIn: Bool, email: String, orgName: String, plan: String) {
        self.loggedIn = loggedIn
        self.email = email
        self.orgName = orgName
        self.plan = plan
    }

    public static func parse(_ data: Data) -> ClaudeAccount? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return ClaudeAccount(loggedIn: json["loggedIn"] as? Bool ?? false, email: json["email"] as? String ?? "",
                             orgName: json["orgName"] as? String ?? "", plan: json["subscriptionType"] as? String ?? "")
    }

    /// 예: "kim@example.com · Example Inc. (enterprise)"
    public var display: String {
        guard loggedIn else { return "로그인 안 됨" }
        let org = orgName.isEmpty ? "" : " · \(orgName)"
        return email + org + (plan.isEmpty ? "" : " (\(plan))")
    }
}
