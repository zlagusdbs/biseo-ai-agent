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
                        if chat.messages.isEmpty {
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
        case .user: return Color(red: 0.73, green: 0.84, blue: 1.0)
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
