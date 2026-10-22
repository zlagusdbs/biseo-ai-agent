import Foundation

public enum ClaudeFailure: Equatable {
    case notInstalled
    case notLoggedIn
    case usageLimit
    case timeout
    case cancelled
    case malformed(String)
    case other(String)

    public var message: String {
        switch self {
        case .notInstalled: return "Claude Code 설치가 필요해요."
        case .notLoggedIn: return "로그인이 필요합니다. 브라우저를 띄웁니다."
        case .usageLimit: return "Claude 사용 한도에 도달했어요."
        case .timeout: return "응답이 늦어요. 다시 시도해 주세요."
        case .cancelled: return "취소했어요."
        case .malformed(let text): return "응답을 읽지 못했어요: \(text.prefix(200))"
        case .other(let text): return "오류가 났어요: \(text.prefix(200))"
        }
    }
}

public enum ClaudeResponse: Equatable {
    case success(text: String, sessionId: String)
    case failure(ClaudeFailure)

    /// `claude -p --output-format json` 출력 해석. JSON 이 아니어도 앱이 죽지 않게 failure 로 돌려준다.
    public static func parse(stdout: Data, exitCode: Int32) -> ClaudeResponse {
        let text = String(decoding: stdout, as: UTF8.self)
        // stream-json: 여러 줄 중 마지막 "type":"result" 줄을 쓴다.
        let resultLine = text.split(separator: "\n").reversed().compactMap { line -> [String: Any]? in
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  o["type"] as? String == "result" else { return nil }
            return o
        }.first
        if let object = resultLine { return interpret(object, exitCode: exitCode) }
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
              let object = try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: Any]
        else {
            return .failure(classify(text) ?? .malformed(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return interpret(object, exitCode: exitCode)
    }

    static func interpret(_ object: [String: Any], exitCode: Int32) -> ClaudeResponse {
        let result = object["result"] as? String ?? ""
        let isError = object["is_error"] as? Bool ?? (exitCode != 0)
        if isError {
            return .failure(classify(result) ?? .other(result))
        }
        return .success(text: result, sessionId: object["session_id"] as? String ?? "")
    }

    static func classify(_ text: String) -> ClaudeFailure? {
        let lower = text.lowercased()
        if lower.contains("authenticate") || lower.contains("/login") || lower.contains("not logged in") {
            return .notLoggedIn
        }
        if lower.contains("usage limit") || lower.contains("rate limit") || lower.contains("limit reached") {
            return .usageLimit
        }
        return nil
    }
}
