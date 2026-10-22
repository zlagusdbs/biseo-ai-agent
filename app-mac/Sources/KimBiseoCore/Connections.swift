import Foundation

/// `kimbiseo status` 출력 한 줄.
public struct SystemStatus: Decodable, Identifiable, Equatable {
    /// external: claude.ai 커넥터처럼 앱이 따로 확인하는 것 (Microsoft 365)
    public enum Status: String, Decodable { case connected, disconnected, expired, unavailable, external }

    public let system: String
    public let name: String
    public let group: String
    public let status: Status
    /// password: 사내 아이디·비밀번호 / gh: GitHub CLI 로그인
    public let auth: String?
    public let baseUrl: String?
    /// 연결 화면에서 묶어 보일 회사 이름 (connections 파일의 company)
    public let company: String?
    public var id: String { system }
}

/// `kimbiseo connect` 출력 한 줄. status: connected / auth_failed / network_unreachable / unavailable
public struct ConnectResult: Decodable, Equatable {
    public let system: String
    public let status: String
    public let message: String

    public init(system: String, status: String, message: String) {
        self.system = system
        self.status = status
        self.message = message
    }
}

public enum ConnectTarget: Equatable {
    case system(String)
    case group(String)

    public var arguments: [String] {
        switch self {
        case .system(let id): return ["connect", id]
        case .group(let group): return ["connect", "--group", group]
        }
    }
}

/// `kimbiseo github review-requests` 출력 한 줄.
public struct PullRequest: Decodable, Equatable {
    public let id: Int
    public let repo: String
    public let number: Int
    public let title: String
    public let author: String
    public let url: String
    public let updated: String
}
