import Foundation

/// 앱 설정과 경로. `~/Library/Application Support/kim-biseo/settings.json` 에 저장한다.
public struct AppSettings: Codable, Equatable {
    /// 비서 이름. 화면 제목과 비서의 자기 소개에 쓴다.
    public var assistantName: String
    public var repoDir: String
    public var claudePath: String
    public var uvPath: String
    public var reportHour: Int
    public var reportMinute: Int
    public var lastReportDay: String?
    public var hotkey: Hotkey = .default
    /// true 면 김비서만 따로 Claude 에 로그인한다 (터미널 Claude Code 로그인과 분리, 다른 조직·플랜 사용 가능).
    public var separateClaudeLogin = false

    public static let defaultAssistantName = "김비서"

    public static let `default` = AppSettings(
        assistantName: defaultAssistantName,
        repoDir: NSString(string: "~/Workspace/kim-biseo").expandingTildeInPath,
        claudePath: NSString(string: "~/.local/bin/claude").expandingTildeInPath,
        uvPath: "/opt/homebrew/bin/uv",
        reportHour: 10,
        reportMinute: 0,
        lastReportDay: nil
    )

    public init(assistantName: String, repoDir: String, claudePath: String, uvPath: String,
                reportHour: Int, reportMinute: Int, lastReportDay: String?) {
        self.assistantName = assistantName
        self.repoDir = repoDir
        self.claudePath = claudePath
        self.uvPath = uvPath
        self.reportHour = reportHour
        self.reportMinute = reportMinute
        self.lastReportDay = lastReportDay
    }

    /// 예전 설정 파일에 없는 항목은 기본값으로 채운다.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.default
        assistantName = try c.decodeIfPresent(String.self, forKey: .assistantName) ?? d.assistantName
        repoDir = try c.decodeIfPresent(String.self, forKey: .repoDir) ?? d.repoDir
        claudePath = try c.decodeIfPresent(String.self, forKey: .claudePath) ?? d.claudePath
        uvPath = try c.decodeIfPresent(String.self, forKey: .uvPath) ?? d.uvPath
        reportHour = try c.decodeIfPresent(Int.self, forKey: .reportHour) ?? d.reportHour
        reportMinute = try c.decodeIfPresent(Int.self, forKey: .reportMinute) ?? d.reportMinute
        lastReportDay = try c.decodeIfPresent(String.self, forKey: .lastReportDay)
        hotkey = try c.decodeIfPresent(Hotkey.self, forKey: .hotkey) ?? .default
        separateClaudeLogin = try c.decodeIfPresent(Bool.self, forKey: .separateClaudeLogin) ?? false
    }
}

public enum AppPaths {
    public static var dataDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("kim-biseo", isDirectory: true)
    }
    public static var workDir: URL { dataDir.appendingPathComponent("work", isDirectory: true) }
    /// 김비서 전용 Claude 로그인 정보가 들어가는 폴더 (separateClaudeLogin 일 때).
    public static var claudeConfigDir: URL { dataDir.appendingPathComponent("claude-config", isDirectory: true) }
    public static var mcpConfig: URL { dataDir.appendingPathComponent("mcp-config.json") }
    public static var settingsFile: URL { dataDir.appendingPathComponent("settings.json") }
    public static var chatFile: URL { dataDir.appendingPathComponent("chat.json") }

    public static func sharedFile(_ name: String, settings: AppSettings) -> URL {
        URL(fileURLWithPath: settings.repoDir).appendingPathComponent("shared").appendingPathComponent(name)
    }

    /// 데이터 폴더를 만들고, 템플릿으로 실제 MCP 설정 파일을 다시 쓴다.
    public static func prepare(settings: AppSettings) throws {
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let template = try String(contentsOf: sharedFile("mcp-config.template.json", settings: settings), encoding: .utf8)
        let config = template
            .replacingOccurrences(of: "{{UV_PATH}}", with: settings.uvPath)
            .replacingOccurrences(of: "{{MCP_SERVER_DIR}}", with: settings.repoDir + "/mcp-server")
        try config.write(to: mcpConfig, atomically: true, encoding: .utf8)
    }

    public static func loadSettings() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsFile),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return .default }
        return settings
    }

    public static func saveSettings(_ settings: AppSettings) {
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(settings).write(to: settingsFile, options: .atomic)
    }

    /// GUI 앱은 터미널과 PATH 가 달라서, 하위 프로세스에 쓸 PATH 를 직접 만든다.
    public static func processEnvironment(settings: AppSettings) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = [
            URL(fileURLWithPath: settings.uvPath).deletingLastPathComponent().path,
            URL(fileURLWithPath: settings.claudePath).deletingLastPathComponent().path,
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
        ]
        env["PATH"] = (extra + [env["PATH"] ?? ""]).filter { !$0.isEmpty }.joined(separator: ":")
        if settings.separateClaudeLogin {
            try? FileManager.default.createDirectory(at: claudeConfigDir, withIntermediateDirectories: true)
            env["CLAUDE_CONFIG_DIR"] = claudeConfigDir.path
        } else {
            env.removeValue(forKey: "CLAUDE_CONFIG_DIR")
        }
        return env
    }
}
