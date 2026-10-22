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
        guard FileManager.default.isExecutableFile(atPath: settings.claudePath),
              let out = try? await ProcessRunner().run(executable: settings.claudePath, arguments: ["auth", "status"],
                                                       environment: AppPaths.processEnvironment(settings: settings),
                                                       timeout: 20),
              let json = try? JSONSerialization.jsonObject(with: out.stdout) as? [String: Any]
        else { return false }
        return json["loggedIn"] as? Bool ?? false
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
