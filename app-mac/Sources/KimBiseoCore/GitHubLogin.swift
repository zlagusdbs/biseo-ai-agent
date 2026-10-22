import Foundation

/// `gh auth login --web` 대신 실행. 한 번용 코드를 화면에 보여 주고, 브라우저에서 승인하면 끝난다.
public final class GitHubLogin: @unchecked Sendable {
    public enum Event: Equatable {
        case code(String)      // 브라우저에 입력할 한 번용 코드
        case finished(Bool)
    }

    private var process: Process?
    private var buffer = ""

    public init() {}

    public static func ghPath() -> String {
        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].first { FileManager.default.isExecutableFile(atPath: $0) } ?? "gh"
    }

    public static func code(in text: String) -> String? {
        guard let range = text.range(of: #"[A-Z0-9]{4}-[A-Z0-9]{4}"#, options: .regularExpression) else { return nil }
        return String(text[range])
    }

    public func start(host: String, settings: AppSettings, onEvent: @escaping (Event) -> Void) {
        cancel()
        buffer = ""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.ghPath())
        process.arguments = ["auth", "login", "--hostname", host, "--web", "--git-protocol", "https"]
        process.environment = AppPaths.processEnvironment(settings: settings)
        let out = Pipe(), input = Pipe()
        process.standardOutput = out
        process.standardError = out
        process.standardInput = input
        var sentCode = false
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            self.buffer += String(decoding: handle.availableData, as: UTF8.self)
            if !sentCode, let code = Self.code(in: self.buffer) {
                sentCode = true
                DispatchQueue.main.async { onEvent(.code(code)) }
            }
            if self.buffer.localizedCaseInsensitiveContains("press enter") {
                input.fileHandleForWriting.write(Data("\n".utf8))
                self.buffer = self.buffer.replacingOccurrences(of: "Press Enter", with: "", options: .caseInsensitive)
            }
        }
        process.terminationHandler = { p in
            out.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { onEvent(.finished(p.terminationStatus == 0)) }
        }
        do {
            try process.run()
            self.process = process
        } catch {
            onEvent(.finished(false))
        }
    }

    public func cancel() {
        if let process, process.isRunning { process.terminate() }
        process = nil
    }
}
