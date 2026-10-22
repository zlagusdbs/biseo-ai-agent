import Foundation

public enum KimbiseoCLIError: Error, LocalizedError {
    case failed(String)
    public var errorDescription: String? {
        if case .failed(let text) = self { return text }
        return nil
    }
}

/// mcp-server 의 `kimbiseo` 명령 실행. 아이디·비밀번호는 표준 입력으로만 넘긴다.
public enum KimbiseoCLI {
    static let timeout: TimeInterval = 30

    public static func status(settings: AppSettings) async throws -> [SystemStatus] {
        let out = try await run(["status"], stdin: nil, settings: settings)
        return try decode([SystemStatus].self, out)
    }

    public static func connect(target: ConnectTarget, username: String, secret: String,
                               settings: AppSettings) async throws -> [ConnectResult] {
        let out = try await run(target.arguments, stdin: "\(username)\n\(secret)\n", settings: settings)
        return try decode([ConnectResult].self, out)
    }

    public static func githubReviewRequests(settings: AppSettings) async throws -> [PullRequest] {
        let out = try await run(["github", "review-requests"], stdin: nil, settings: settings)
        return try decode([PullRequest].self, out)
    }

    public static func events(_ eventId: String, settings: AppSettings) async throws -> [EventItem] {
        let out = try await run(["events", eventId], stdin: nil, settings: settings)
        return try decode([EventItem].self, out)
    }

    private static func run(_ args: [String], stdin: String?, settings: AppSettings) async throws -> ProcessOutput {
        let out = try await ProcessRunner().run(
            executable: settings.uvPath,
            arguments: ["--directory", settings.repoDir + "/mcp-server", "run", "--quiet", "kimbiseo"] + args,
            stdin: stdin,
            environment: AppPaths.processEnvironment(settings: settings),
            timeout: timeout
        )
        if out.timedOut { throw KimbiseoCLIError.failed("연결 확인이 너무 오래 걸려요") }
        return out
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ out: ProcessOutput) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: out.stdout)
        } catch {
            let err = String(decoding: out.stderr, as: UTF8.self)
            let text = String(decoding: out.stdout, as: UTF8.self)
            throw KimbiseoCLIError.failed((err.isEmpty ? text : err).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
