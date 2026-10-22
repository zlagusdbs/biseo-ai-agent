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

    /// 이슈 등록. 사용자가 확인 카드에서 [Jira에 등록]을 눌렀을 때만 부른다.
    public static func jiraCreate(_ draft: JiraDraft, settings: AppSettings) async throws -> JiraCreated {
        let input = String(decoding: try JSONEncoder().encode(draft), as: UTF8.self)
        let out = try await run(["jira", "create"], stdin: input, settings: settings)
        if let created = try? JSONDecoder().decode(JiraCreated.self, from: out.stdout) { return created }
        struct Failure: Decodable { let error: String; let detail: String? }
        if let failure = try? JSONDecoder().decode(Failure.self, from: out.stdout) {
            throw KimbiseoCLIError.failed(JiraFailure.message(code: failure.error, detail: failure.detail ?? ""))
        }
        return try decode(JiraCreated.self, out)
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

/// 이슈 등록 실패를 사람이 읽는 말로.
public enum JiraFailure {
    public static func message(code: String, detail: String) -> String {
        switch code {
        case "NOT_CONNECTED:jira": return "Jira 연결이 필요해요. 연결 메뉴에서 연결해 주세요."
        case "AUTH_EXPIRED:jira": return "Jira 연결이 만료됐어요. 연결 메뉴에서 다시 연결해 주세요."
        case "NETWORK_UNREACHABLE:jira": return "사내망 연결을 확인해 주세요."
        case "REJECTED:jira": return "Jira 가 등록을 거절했어요: \(detail)"
        default: return detail.isEmpty ? "등록하지 못했어요 (\(code))" : "등록하지 못했어요: \(detail)"
        }
    }
}
