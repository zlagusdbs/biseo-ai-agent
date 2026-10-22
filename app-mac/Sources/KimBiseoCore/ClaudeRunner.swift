import Foundation

/// `claude -p` 를 한 번 실행하고 결과를 해석한다.
public final class ClaudeRunner: @unchecked Sendable {
    public static let timeout: TimeInterval = 120

    private let process = ProcessRunner()
    private var cancelled = false

    public init() {}

    public func run(prompt: String, images: [ImageAttachment] = [], sessionId: String?, settings: AppSettings) async -> ClaudeResponse {
        cancelled = false
        guard FileManager.default.isExecutableFile(atPath: settings.claudePath) else {
            return .failure(.notInstalled)
        }
        do {
            try AppPaths.prepare(settings: settings)
            let name = settings.assistantName.trimmingCharacters(in: .whitespacesAndNewlines)
            var systemPrompt = try String(contentsOf: AppPaths.sharedFile("prompts/system.md", settings: settings), encoding: .utf8)
            if !name.isEmpty && name != AppSettings.defaultAssistantName {
                systemPrompt += "\n- 사용자가 네 이름을 \"\(name)\"(으)로 바꿨다. 자신을 \"\(name)\"(이)라고 부른다.\n"
            }
            let owner = settings.ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !owner.isEmpty {
                systemPrompt += "\n- 주인(사용자)의 이름은 \(owner)이다. 부를 때는 \"\(owner)님\"이라고 한다.\n"
            }
            systemPrompt += Rules.prompt()
            let args = ClaudeCommand.arguments(sessionId: sessionId,
                                               mcpConfigPath: AppPaths.mcpConfig.path, systemPrompt: systemPrompt)
            let out = try await process.run(executable: settings.claudePath, arguments: args,
                                            stdin: ClaudeCommand.inputLine(prompt: prompt, images: images),
                                            workDir: AppPaths.workDir,
                                            environment: AppPaths.processEnvironment(settings: settings),
                                            timeout: Self.timeout)
            if cancelled { return .failure(.cancelled) }
            if out.timedOut { return .failure(.timeout) }
            let response = ClaudeResponse.parse(stdout: out.stdout, exitCode: out.exitCode)
            if case .failure(.malformed(let text)) = response, text.isEmpty {
                return .failure(.other(String(decoding: out.stderr, as: UTF8.self)))
            }
            return response
        } catch {
            return .failure(.other(error.localizedDescription))
        }
    }

    public func cancel() {
        cancelled = true
        process.cancel()
    }
}
