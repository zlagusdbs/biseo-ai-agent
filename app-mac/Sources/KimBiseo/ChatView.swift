import KimBiseoCore
import SwiftUI

struct ChatView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var chat: ChatSession
    @State private var input = ""
    @FocusState private var inputFocused: Bool
    @State private var pending: [ImageAttachment] = []
    @State private var dropTargeted = false
    @State private var editingName = false
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if editingName {
                    TextField("이름", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 180)
                        .focused($nameFocused)
                        .onSubmit(saveName)
                        .onExitCommand { editingName = false }
                    Button("저장", action: saveName)
                        .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("취소") { editingName = false }
                } else {
                    Text(model.settings.assistantName).font(.headline)
                    Button {
                        draftName = model.settings.assistantName
                        editingName = true
                        nameFocused = true
                    } label: { Image(systemName: "pencil") }
                        .buttonStyle(.borderless)
                        .help("이름 바꾸기")
                }
                Spacer()
                Button("새 대화") { chat.newConversation() }
                    .disabled(chat.messages.isEmpty && !chat.isBusy)
            }
            .padding(12)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if model.settings.ownerName.isEmpty {
                            OnboardingCard(model: model, chat: chat)
                        } else if chat.messages.isEmpty {
                            Text("무엇이든 물어보세요. 예: 내 미완료 Jira 알려줘")
                                .foregroundStyle(.secondary)
                                .padding(.top, 40)
                                .frame(maxWidth: .infinity)
                        }
                        ForEach(chat.messages) { message in
                            MessageRow(message: message) { system in
                                model.selected = .connections
                                _ = system
                            }
                            .id(message.id)
                            if !message.alarms.isEmpty {
                                AlarmProposalCard(alarms: message.alarms,
                                                  registered: message.alarms.allSatisfy { a in model.alarms.contains { $0.id == a.id } },
                                                  register: { model.register(message.alarms) },
                                                  open: { model.selected = .alarms })
                            }
                            if !message.rules.isEmpty {
                                RuleProposalCard(notes: message.rules, saved: message.rulesSaved) {
                                    for note in message.rules {
                                        if note.isForget { try? Memory.forget(note.text, in: note.file) }
                                        else if note.isMemory { try? Memory.add(note.text) }
                                        else { try? Rules.append(note.text, to: note.file) }
                                    }
                                    chat.update(message.id) { $0.rulesSaved = true }
                                }
                            }
                            if !message.worklogs.isEmpty {
                                WorklogCard(model: model, chat: chat, messageID: message.id,
                                            drafts: message.worklogs, done: Set(message.worklogsDone))
                            }
                            if let draft = message.jira {
                                JiraDraftCard(model: model, chat: chat, messageID: message.id, draft: draft,
                                              proposedDefaults: message.jiraDefaults, created: message.jiraCreated)
                            }
                        }
                        if chat.isBusy {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("생각 중…").foregroundStyle(.secondary)
                                Button("취소") { chat.cancel() }.buttonStyle(.link)
                            }
                            .id("busy")
                        }
                        if chat.loginState != .idle {
                            LoginBox(chat: chat).id("login")
                        }
                        if chat.lastFailedPrompt != nil && !chat.isBusy {
                            Button("다시 시도") { chat.retry() }
                        }
                        Color.clear.frame(height: 1).id(Self.bottomID)
                    }
                    .padding(12)
                }
                .defaultScrollAnchor(.bottom)
                .background(Color(red: 0.89, green: 0.94, blue: 1.0))   // 대화 영역: 파스텔 파란색
                // 처음 열 때, 메시지가 늘 때, "생각 중"·로그인 상자가 나타날 때 항상 맨 아래로
                .onAppear { scrollToBottom(proxy, animated: false) }
                .onChange(of: chat.messages.count) { scrollToBottom(proxy) }
                .onChange(of: chat.isBusy) { scrollToBottom(proxy) }
                .onChange(of: chat.loginState) { scrollToBottom(proxy) }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                if !pending.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(pending, id: \.path) { image in
                                Thumbnail(path: image.path, size: 56)
                                    .overlay(alignment: .topTrailing) {
                                        Button { pending.removeAll { $0.path == image.path } } label: {
                                            Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.6))
                                        }
                                        .buttonStyle(.plain).padding(2)
                                    }
                            }
                        }
                    }
                }
                HStack(spacing: 8) {
                    Button { add(ImageLoader.chooseFiles()) } label: { Image(systemName: "paperclip").font(.title3) }
                        .buttonStyle(.plain)
                        .help("이미지 첨부 (⌘V 붙여넣기, 끌어다 놓기도 돼요)")
                    TextField("메시지 입력", text: $input, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .focused($inputFocused)
                        .onSubmit(send)
                    Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                        .buttonStyle(.plain)
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pending.isEmpty)
                }
            }
            .padding(12)
            .background(Color.white)                                 // 입력칸: 흰색
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .background(Color.accentColor.opacity(0.06))
                    .overlay(Text("여기에 놓으면 이미지를 첨부해요").font(.headline))
                    .padding(6)
            }
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .onReceive(NotificationCenter.default.publisher(for: .kimBiseoPasteImages)) { _ in
            add(ImageLoader.fromPasteboard())
        }
        .onAppear { inputFocused = true }
    }

    private static let bottomID = "chat-bottom"

    private func saveName() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        model.settings.assistantName = String(name.prefix(20))
        editingName = false
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        // 레이아웃이 끝난 뒤에 이동해야 마지막 줄까지 내려간다.
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            } else {
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
        }
    }

    private func send() {
        chat.send(input, images: pending)
        input = ""
        pending = []
    }

    private func add(_ images: [ImageAttachment]) {
        pending = Array((pending + images).prefix(ImageLoader.maxCount))
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, let image = ImageLoader.load(url: url) else { return }
                    DispatchQueue.main.async { add([image]) }
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                    guard let nsImage = object as? NSImage, let image = ImageLoader.attachment(from: nsImage) else { return }
                    DispatchQueue.main.async { add([image]) }
                }
            }
        }
    }
}

private struct MessageRow: View {
    let message: ChatMessage
    let onReconnect: (String) -> Void

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            if !message.images.isEmpty {
                HStack(spacing: 6) {
                    ForEach(message.images, id: \.self) { Thumbnail(path: $0, size: 120) }
                }
            }
            if !message.text.isEmpty {
            Text(LocalizedStringKey(message.text))
                .textSelection(.enabled)
                .padding(10)
                .background(background, in: RoundedRectangle(cornerRadius: 10))
            }
            ForEach(ToolErrorCode.detect(in: message.text), id: \.self) { code in
                switch code {
                case .authExpired(let system), .notConnected(let system):
                    Button("\(system) 다시 연결") { onReconnect(system) }
                case .networkUnreachable:
                    EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var background: Color {
        switch message.role {
        case .user: return Color(red: 1.0, green: 0.93, blue: 0.66)     // 내 말풍선: 연한 노랑 (파란 선택 표시가 잘 보이게)
        case .assistant: return Color.white
        case .error: return Color.red.opacity(0.15)
        }
    }
}

/// 답변이 제안한 알림. [알림에 등록]을 눌러야 알림 메뉴에 들어간다.
private struct AlarmProposalCard: View {
    let alarms: [Alarm]
    let registered: Bool
    let register: () -> Void
    let open: () -> Void

    /// 들어갈 그룹. 직접 말한 이름, 없으면 같은 제목 여러 개일 때 그 제목 (AppModel.register 와 같은 규칙).
    private var groupName: String? {
        if let named = alarms.compactMap(\.group).first { return named }
        return alarms.count > 1 && Set(alarms.map(\.title)).count == 1 ? alarms[0].title : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Label("알림 \(alarms.count)개", systemImage: "bell.badge").font(.callout.weight(.medium))
                if let group = groupName {
                    Label(group, systemImage: "folder").font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(alarms) { alarm in
                HStack(spacing: 6) {
                    Text(alarm.timeText).monospacedDigit()
                    Text(alarm.repeatRule.description).foregroundStyle(.secondary)
                    Text(alarm.title).lineLimit(1)
                }
                .font(.callout)
            }
            HStack {
                if registered {
                    Label("알림 메뉴에 등록했어요", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Button("알림 보기", action: open).buttonStyle(.link)
                } else {
                    Button("알림에 등록", action: register).buttonStyle(.borderedProminent)
                }
            }
            .padding(.top, 2)
        }
        .padding(10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.4)))
    }
}

/// 답변이 제안한 Jira 이슈 초안. [Jira에 등록]을 눌러야 등록되고, [수정]으로 고칠 수 있다.
private struct JiraDraftCard: View {
    @ObservedObject var model: AppModel
    let chat: ChatSession
    let messageID: UUID
    let draft: JiraDraft
    let proposedDefaults: JiraDefaults?
    let created: JiraCreated?
    @State private var saveDefaults = true
    @State private var working = false
    @State private var error: String?
    @State private var editing = false
    @State private var showDescription = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Label("Jira 이슈", systemImage: "square.and.pencil").font(.callout.weight(.medium))
                Text("\(draft.project) · \(draft.issueType)").font(.caption.weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            Text(draft.summary).font(.body.weight(.semibold)).textSelection(.enabled)
            Label("담당자 나 (연결된 Jira 계정)", systemImage: "person").font(.caption).foregroundStyle(.secondary)
            if !draft.periodText.isEmpty {
                Label(draft.periodText, systemImage: "calendar").font(.caption).foregroundStyle(.secondary)
            }
            if !draft.epicLink.isEmpty {
                Label("Epic \(draft.epicLink)", systemImage: "link").font(.caption).foregroundStyle(.secondary)
            }
            if !draft.description.isEmpty {
                DisclosureGroup(isExpanded: $showDescription) {
                    Text(draft.description).font(.caption.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                } label: { Text("설명").font(.caption).foregroundStyle(.secondary) }
            }
            if let proposedDefaults, created == nil {
                Toggle(isOn: $saveDefaults) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("이 설정을 기본값으로 저장").font(.caption.weight(.medium))
                        Text(proposedDefaults.summary(now: Date(), calendar: .current)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                if let created {
                    Label("\(created.key) 등록했어요", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Button("열기") { if let url = URL(string: created.url) { NSWorkspace.shared.open(url) } }.buttonStyle(.link)
                } else {
                    Button(action: create) {
                        if working { ProgressView().controlSize(.small) } else { Text("Jira에 등록") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(working)
                    Button("수정") { editing = true }.disabled(working)
                }
            }
            .padding(.top, 2)
        }
        .padding(10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.4)))
        .sheet(isPresented: $editing) {
            JiraDraftEditor(draft: draft) { edited in chat.update(messageID) { $0.jira = edited } }
        }
    }

    private func create() {
        working = true
        error = nil
        Task {
            do {
                let result = try await KimbiseoCLI.jiraCreate(draft, settings: model.settings)
                chat.update(messageID) { $0.jiraCreated = result }
                if let proposedDefaults, saveDefaults { model.jiraDefaults = proposedDefaults }
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}

/// 초안 고치기.
private struct JiraDraftEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: JiraDraft
    let onSave: (JiraDraft) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Jira 이슈 수정").font(.headline)
            Form {
                field("프로젝트 키", $draft.project, "예: MYPROJ")
                field("이슈 유형", $draft.issueType, "예: Story, Task")
                field("제목", $draft.summary, "")
                VStack(alignment: .leading, spacing: 4) {
                    Text("설명 (Jira 위키 문법)").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $draft.description).font(.body.monospaced()).frame(minHeight: 140)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                }
                field("Original Estimate", $draft.originalEstimate, "예: 365d, 2w, 4h")
                field("Target start", $draft.targetStart, "yyyy-MM-dd, 비우면 안 넣음")
                field("Target end", $draft.targetEnd, "yyyy-MM-dd, 비우면 안 넣음")
                field("Epic Link", $draft.epicLink, "예: MYPROJ-100, 비우면 안 넣음")
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("저장") { onSave(draft); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.isComplete)
            }
        }
        .padding(20)
        .frame(width: 520, height: 620)
    }

    private func field(_ title: String, _ text: Binding<String>, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField("", text: text, prompt: Text(hint)).textFieldStyle(.roundedBorder).labelsHidden()
        }
    }
}

/// 처음 사용: 주인 이름을 묻고 인사한다. Claude 를 부르지 않는다.
private struct OnboardingCard: View {
    @ObservedObject var model: AppModel
    let chat: ChatSession
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("👋 안녕하세요! 저는 \(model.settings.assistantName)예요.").font(.headline)
            Text("앞으로 Jira, Wiki, 근무일정, 배포, 메일 같은 업무를 같이 챙겨 드릴게요.\n먼저, 주인님 이름이 어떻게 되세요?")
            HStack {
                TextField("", text: $name, prompt: Text("이름. 예: 홍길동"))
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(save)
                Button("반가워요", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.4)))
        .onAppear { focused = true }
    }

    private func save() {
        let owner = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty else { return }
        model.settings.ownerName = String(owner.prefix(20))
        chat.say("""
            반가워요, \(model.settings.ownerName)님! 🙌 앞으로 잘 부탁드려요.

            **먼저 해 주세요**
            - 오른쪽 🔌 연결 → [일괄 연동] 으로 사내 계정을 연결해 주세요. 그래야 Jira·Wiki·근무일정을 볼 수 있어요.

            **이렇게 말해 보세요**
            - 내 미완료 Jira 알려줘
            - 평일 9시에 이번 주 근무일정 알려줘 (알림 등록)
            - 지라 등록해줘: 쿠폰 API 응답 필드 추가 (처음엔 기본값을 여쭤봐요)
            - 앞으로 지라 제목 앞에 [회의] 붙여줘 (규칙으로 기억)
            """)
    }
}

/// 답변이 제안한 규칙. [규칙에 저장]을 눌러야 이 Mac 의 규칙 파일에 들어간다.
private struct RuleProposalCard: View {
    let notes: [RuleNote]
    let saved: Bool
    let save: () -> Void

    /// 기억만 / 잊기만 / 그 밖(규칙)에 따라 제목·버튼 말을 바꾼다.
    private var kind: (title: String, symbol: String, button: String, done: String) {
        if notes.allSatisfy(\.isForget) { return ("잊기", "eraser", "잊기", "지웠어요") }
        if notes.allSatisfy(\.isMemory) { return ("기억", "brain", "기억하기", "기억했어요. 새 대화에서도 알아요") }
        return ("규칙", "pin", "규칙에 저장", "저장했어요. 다음 대화부터 늘 적용돼요")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("\(kind.title) \(notes.count)개", systemImage: kind.symbol).font(.callout.weight(.medium))
            ForEach(notes, id: \.self) { note in
                HStack(alignment: .top, spacing: 6) {
                    Text(note.isForget ? "지울 것" : note.isMemory ? "기억" : "\(note.file).md")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text(note.text).font(.callout).strikethrough(note.isForget)
                }
            }
            HStack {
                if saved {
                    Label(kind.done, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Button("폴더 열기") { NSWorkspace.shared.open(Rules.myDir) }.buttonStyle(.link)
                } else {
                    Button(kind.button, action: save).buttonStyle(.borderedProminent)
                }
            }
            .padding(.top, 2)
        }
        .padding(10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.4)))
    }
}

/// 답변이 제안한 worklog. [기록하기]를 눌러야 Jira 에 기록된다. 이미 기록한 건 다시 보내지 않는다.
private struct WorklogCard: View {
    @ObservedObject var model: AppModel
    let chat: ChatSession
    let messageID: UUID
    let drafts: [WorklogDraft]
    let done: Set<String>
    @State private var working = false
    @State private var error: String?

    private var total: Int { drafts.map(\.minutes).reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Label("Work log \(drafts.count)건", systemImage: "clock.badge.checkmark").font(.callout.weight(.medium))
                Text("합계 \(total / 60)시간\(total % 60 > 0 ? " \(total % 60)분" : "")").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(drafts) { draft in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: done.contains(draft.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(done.contains(draft.id) ? Color.green : Color.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(draft.issueKey)\(draft.summary.isEmpty ? "" : " · \(draft.summary)")").font(.callout.weight(.medium))
                        Text("\(draft.date) \(draft.timeText)\(draft.comment.isEmpty ? "" : " · \(draft.comment)")")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                if drafts.allSatisfy({ done.contains($0.id) }) {
                    Label("Jira 에 기록했어요", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button(action: record) {
                        if working { ProgressView().controlSize(.small) } else { Text("기록하기") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(working)
                }
            }
            .padding(.top, 2)
        }
        .padding(10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.4)))
    }

    private func record() {
        working = true
        error = nil
        Task {
            for draft in drafts where !done.contains(draft.id) {
                do {
                    try await KimbiseoCLI.jiraWorklog(draft, settings: model.settings)
                    chat.update(messageID) { $0.worklogsDone.append(draft.id) }
                } catch {
                    self.error = "\(draft.issueKey) \(draft.start): \(error.localizedDescription)"
                    break
                }
            }
            working = false
        }
    }
}

/// 로그인 진행 상자. 브라우저에 나온 코드를 붙여넣으면 claude 에게만 전달하고 지운다.
private struct LoginBox: View {
    @ObservedObject var chat: ChatSession
    @State private var code = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch chat.loginState {
            case .waitingBrowser:
                Label("브라우저에서 회사 계정으로 로그인하고 승인해 주세요.", systemImage: "safari")
            case .needsCode:
                Text("브라우저에 나온 코드를 붙여넣어 주세요.")
                HStack {
                    RomanTextField(placeholder: "코드", text: $code, secure: true, onSubmit: submit)
                    Button("확인", action: submit).disabled(code.isEmpty)
                }
            case .verifying:
                HStack { ProgressView().controlSize(.small); Text("로그인 확인 중…") }
            case .idle:
                EmptyView()
            }
            Button("로그인 취소") { chat.cancelLogin() }.buttonStyle(.link)
        }
        .padding(10)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func submit() {
        chat.submitLoginCode(code)
        code = ""
    }
}

/// 첨부 이미지 미리보기. 누르면 미리보기 앱으로 크게 연다.
private struct Thumbnail: View {
    let path: String
    let size: CGFloat

    var body: some View {
        Group {
            if let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.08)))
        .onTapGesture { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
    }
}
