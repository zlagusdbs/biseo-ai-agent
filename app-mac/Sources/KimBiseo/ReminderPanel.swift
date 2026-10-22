import AppKit
import KimBiseoCore
import SwiftUI

/// 화면 오른쪽 아래 "김비서 알림" 창. 맨 위에 떠 있지만 입력 포커스는 가져가지 않는다.
@MainActor
final class ReminderPanelController {
    private let center: ReminderCenter
    private let panel: NSPanel
    private let hosting: NSHostingView<ReminderListView>
    static let width: CGFloat = 340

    init(center: ReminderCenter, openChat: @escaping () -> Void) {
        self.center = center
        hosting = NSHostingView(rootView: ReminderListView(center: center, openChat: openChat))
        panel = NonActivatingPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200),
                                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        center.onChange = { [weak self] in self?.refresh() }
    }

    /// 항상 노트북(내장) 화면. 없으면 메뉴 막대가 있는 주 화면.
    /// NSScreen.main 은 "지금 작업 중인 창이 있는 화면"이라 쓰면 매번 다른 모니터에 뜬다.
    static func targetScreen() -> NSScreen {
        let builtIn = NSScreen.screens.first { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
            return CGDisplayIsBuiltin(id) != 0
        }
        return builtIn ?? NSScreen.screens.first ?? NSScreen.main!
    }

    func refresh() {
        guard !center.visible.isEmpty else { panel.orderOut(nil); return }
        hosting.layoutSubtreeIfNeeded()
        let height = min(hosting.fittingSize.height, 520)
        let screen = Self.targetScreen().visibleFrame
        panel.setFrame(NSRect(x: screen.maxX - Self.width - 16, y: screen.minY + 16, width: Self.width, height: height),
                       display: true)
        panel.orderFrontRegardless()
    }
}

private final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }   // 다시 알림 메뉴가 열리도록
}

private enum Palette {
    static let background = Color(red: 0.89, green: 0.94, blue: 1.0)
    static let title = Color(red: 0.02, green: 0.17, blue: 0.33)
    static let sub = Color(red: 0.09, green: 0.37, blue: 0.65)
    static let line = Color(red: 0.52, green: 0.72, blue: 0.92)
    static let accent = Color(red: 0.22, green: 0.54, blue: 0.87)
}

struct ReminderListView: View {
    @ObservedObject var center: ReminderCenter
    let openChat: () -> Void

    var body: some View {
        let items = center.visible
        VStack(alignment: .leading, spacing: 8) {
            Label("김비서 알림 \(items.count)", systemImage: "bell")
                .font(.callout.weight(.medium))
                .foregroundStyle(Palette.title)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        ReminderCard(item: item, center: center, openChat: openChat)
                    }
                }
            }
            .frame(maxHeight: 400)
            .fixedSize(horizontal: false, vertical: items.count <= 3)
            HStack {
                Spacer()
                Button("모두 확인") { center.dismissAll() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Palette.sub)
            }
        }
        .padding(12)
        .frame(width: ReminderPanelController.width)
        .background(Palette.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line.opacity(0.6), lineWidth: 0.5))
    }
}

private struct ReminderCard: View {
    let item: Reminder
    @ObservedObject var center: ReminderCenter
    let openChat: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title).font(.callout.weight(.medium)).foregroundStyle(Palette.title).lineLimit(1)
            Text("\(item.summary) · \(item.firedAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(item.failed ? Color.red : Palette.sub)
                .lineLimit(2)
            HStack(spacing: 6) {
                if let link = item.url, let url = URL(string: link) {
                    Button("열기") { NSWorkspace.shared.open(url); center.dismiss(item.id) }
                        .buttonStyle(ChipStyle(filled: false))
                } else {
                    Button("자세히") { openChat() }
                        .buttonStyle(ChipStyle(filled: false))
                }
                Menu {
                    ForEach(ReminderQueue.snoozeChoices, id: \.self) { minutes in
                        Button(minutes >= 60 ? "\(minutes / 60)시간 뒤" : "\(minutes)분 뒤") {
                            center.snooze(item.id, minutes: minutes)
                        }
                    }
                } label: {
                    Text("10분 뒤 ▾")
                } primaryAction: {
                    center.snooze(item.id, minutes: 10)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.line, lineWidth: 0.5))
                Spacer()
                Button("확인") { center.dismiss(item.id) }
                    .buttonStyle(ChipStyle(filled: true))
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ChipStyle: ButtonStyle {
    let filled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(filled ? Color.white : Palette.title)
            .background(filled ? Palette.accent : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(filled ? Color.clear : Palette.line, lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
