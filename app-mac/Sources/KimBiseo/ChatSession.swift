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
        trimmed += ChatHints.for(trimmed, now: Date(), calendar: .current)
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

    /// Claude 를 부르지 않고 김비서 말로 바로 붙인다 (처음 인사 등).
    func say(_ text: String) {
        append(ChatMessage(role: .assistant, text: text))
    }

    /// 계정이 바뀌면 이전 세션을 이어 쓸 수 없어서 세션만 잊는다 (화면의 대화는 남김).
    func forgetSession() {
        sessionId = nil
        save()
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
            let (afterAlarms, alarms) = AlarmProposal.extract(from: text)
            let (afterJira, jira) = JiraProposal.extract(from: afterAlarms)
            let (afterRules, rules) = RuleProposal.extract(from: afterJira)
            let (clean, worklogs) = WorklogProposal.extract(from: afterRules)
            var message = ChatMessage(role: .assistant, text: clean, alarms: alarms, jira: jira)
            message.rules = rules
            message.worklogs = worklogs
            append(message)
        case .failure(let failure):
            append(ChatMessage(role: .error, text: failure.message))
            lastFailedImages = images
            if failure == .notLoggedIn {
                startLogin(retry: prompt)
            } else if failure != .cancelled && failure != .usageLimit {   // 한도는 다시 시도해도 같아서 버튼을 숨긴다
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

    /// 카드에서 초안을 고치거나 등록했을 때 그 메시지를 바꿔 저장한다.
    func update(_ id: UUID, _ change: (inout ChatMessage) -> Void) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        change(&messages[i])
        save()
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
