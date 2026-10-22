import Foundation

/// 답변에 들어 있는 MCP 도구 오류 코드. 화면에서 [다시 연결] 같은 버튼을 띄우는 데 쓴다.
public enum ToolErrorCode: Equatable, Hashable {
    case authExpired(String)
    case networkUnreachable(String)
    case notConnected(String)

    public var system: String {
        switch self {
        case .authExpired(let s), .networkUnreachable(let s), .notConnected(let s): return s
        }
    }

    public static func detect(in text: String) -> [ToolErrorCode] {
        let pattern = #"(AUTH_EXPIRED|NETWORK_UNREACHABLE|NOT_CONNECTED):([a-z0-9_-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var found: [ToolErrorCode] = []
        for match in regex.matches(in: text, range: range) {
            guard let kindRange = Range(match.range(at: 1), in: text),
                  let systemRange = Range(match.range(at: 2), in: text) else { continue }
            let system = String(text[systemRange])
            let code: ToolErrorCode
            switch text[kindRange] {
            case "AUTH_EXPIRED": code = .authExpired(system)
            case "NETWORK_UNREACHABLE": code = .networkUnreachable(system)
            default: code = .notConnected(system)
            }
            if !found.contains(code) { found.append(code) }
        }
        return found
    }
}
