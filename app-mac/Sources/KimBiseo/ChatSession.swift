import Foundation
import KimBiseoCore

/// 채팅 상태. 질문은 한 번에 하나씩 처리하고, 처리 중 들어온 요청은 순서대로 기다린다.
@MainActor
final class ChatSession: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isBusy = false
    @Published private(set) var lastFailedPrompt: String?
    private var lastFailedImages: [ImageAttachment] = []
    @Published private(set) var loginState: LoginState = .idle

    enum LoginState { case idle, waitingBrowser, needsCode, verifying }

    private enum Job {
        case chat(String, [ImageAttachment])
        case report(title: String, prompt: String, (ClaudeResponse) -> Void)
    }

    private struct Stored: Codable {
        var messages: [ChatMessage]
        var sessionId: String?
    }

    private var sessionId: String?
    private var queue: [Job] = []
    private let runner = ClaudeRunner()
    private let login = ClaudeLogin()
    private let settings: () -> AppSettings

    init(settings: @escaping () -> AppSettings) {
        self.settings = settings
        if let data = try? Data(contentsOf: AppPaths.chatFile),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            messages = stored.messages
            sessionId = stored.sessionId
        }
    }

    func send(_ text: String, images: [ImageAttachment] = []) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !images.isEmpty else { return }
        if trimmed.isEmpty { trimmed = "이 이미지를 보고 설명해줘." }
        append(ChatMessage(role: .user, text: text.trimmingCharacters(in: .whitespacesAndNewlines), images: images.map(\.path)))
        queue.append(.chat(trimmed, images))
        processNext()
    }

    /// 알림 실행. 새 세션으로 실행해 결과를 채팅창에 이어 붙이고, 이후 대화는 그 결과에서 이어간다.
    func runReport(title: String, prompt: String, completion: @escaping (ClaudeResponse) -> Void) {
        queue.append(.report(title: title, prompt: prompt, completion))
        processNext()
    }

    func retry() {
        guard let prompt = lastFailedPrompt else { return }
        lastFailedPrompt = nil
        queue.append(.chat(prompt, lastFailedImages))
        processNext()
    }

    func cancel() {
        queue.removeAll()
        runner.cancel()
    }

    func newConversation() {
        cancel()
        messages = []
        sessionId = nil
        lastFailedPrompt = nil
        save()
    }

    private func processNext() {
        guard !isBusy, !queue.isEmpty else { return }
        isBusy = true
        let job = queue.removeFirst()
        Task {
            switch job {
            case .chat(let prompt, let images):
                let response = await runner.run(prompt: prompt, images: images, sessionId: sessionId, settings: settings())
                handle(response, prompt: prompt, images: images)
            case .report(let title, let prompt, let completion):
                append(ChatMessage(role: .user, text: "🔔 \(title)"))
                let response = await runner.run(prompt: prompt, sessionId: nil, settings: settings())
                handle(response, prompt: nil, images: [])
                completion(response)
            }
            isBusy = false
            processNext()
        }
    }

    private func handle(_ response: ClaudeResponse, prompt: String?, images: [ImageAttachment]) {
        switch response {
        case .success(let text, let newSession):
            if !newSession.isEmpty { sessionId = newSession }
            let (clean, alarms) = AlarmProposal.extract(from: text)
            append(ChatMessage(role: .assistant, text: clean, alarms: alarms))
        case .failure(let failure):
            append(ChatMessage(role: .error, text: failure.message))
            lastFailedImages = images
            if failure == .notLoggedIn {
                startLogin(retry: prompt)
            } else if failure != .cancelled {
                lastFailedPrompt = prompt
            }
        }
    }

    // MARK: 로그인

    /// `claude auth login` 을 실행해 브라우저를 띄우고, 로그인되면 질문을 다시 보낸다.
    func startLogin(retry prompt: String?) {
        loginState = .waitingBrowser
        login.start(settings: settings()) { [weak self] event in
            guard let self else { return }
            switch event {
            case .browserOpened:
                break
            case .needsCode:
                if self.loginState == .waitingBrowser { self.loginState = .needsCode }
            case .finished(let ok):
                self.loginState = .idle
                if ok {
                    self.append(ChatMessage(role: .assistant, text: "로그인됐어요."))
                    if let prompt {
                        self.queue.append(.chat(prompt, self.lastFailedImages))
                        self.processNext()
                    }
                } else {
                    self.append(ChatMessage(role: .error, text: "로그인하지 못했어요. 다시 시도해 주세요."))
                    self.lastFailedPrompt = prompt
                }
            }
        }
    }

    func submitLoginCode(_ code: String) {
        loginState = .verifying
        login.submit(code: code)
    }

    func cancelLogin() {
        login.cancel()
        loginState = .idle
    }

    private func append(_ message: ChatMessage) {
        messages.append(message)
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: AppPaths.dataDir, withIntermediateDirectories: true)
        let stored = Stored(messages: messages, sessionId: sessionId)
        try? JSONEncoder().encode(stored).write(to: AppPaths.chatFile, options: .atomic)
    }
}
