import Foundation

/// claude.ai 커넥터(예: Microsoft 365) 연결 상태. `claude mcp list` 출력으로 판단한다.
public enum ConnectorStatus {
    public static let microsoft365 = "Microsoft 365"
    public static let settingsURL = URL(string: "https://claude.ai/settings/connectors")!

    public static func parse(output: String, name: String) -> SystemStatus.Status {
        guard let line = output.split(separator: "\n").first(where: { $0.contains("claude.ai \(name):") }) else {
            return .disconnected
        }
        return line.contains("Connected") && !line.contains("Needs authentication") ? .connected : .disconnected
    }

    public static func check(name: String, settings: AppSettings) async -> SystemStatus.Status {
        guard FileManager.default.isExecutableFile(atPath: settings.claudePath),
              let out = try? await ProcessRunner().run(executable: settings.claudePath, arguments: ["mcp", "list"],
                                                       workDir: AppPaths.workDir,
                                                       environment: AppPaths.processEnvironment(settings: settings),
                                                       timeout: 60)
        else { return .disconnected }
        return parse(output: String(decoding: out.stdout, as: UTF8.self), name: name)
    }
}
