import AppKit
import Combine
import SwiftUI

/// Esc 로 닫히고, 배경을 끌어서 옮길 수 있는 김비서 창.
final class KimBiseoPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

/// 메뉴바 아이콘 + 채팅 창. 아이콘 클릭이나 ⇧⌃⌥⌘ Space 로 열고 닫는다. 창 위치는 기억한다.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem!
    private var panel: KimBiseoPanel!
    private let hotkey = HotkeyManager()
    private var notifier: Notifier!
    private var scheduler: AlarmScheduler!
    private let reminders = ReminderCenter()
    private var reminderPanel: ReminderPanelController!
    private var triggers: TriggerWatcher!
    private var hotkeyWatch: AnyCancellable?

    private var keyMonitor: Any?

    /// 메뉴바 앱이라 기본 메뉴가 없어서, ⌘C·⌘V 등이 동작하도록 편집 메뉴를 직접 만든다.
    private func installEditMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "창 닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "김비서 숨기기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "김비서 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "편집")
        edit.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "다시 실행", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "오려두기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "복사하기", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "모두 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    /// 클립보드에 이미지가 있을 때 ⌘V 는 이미지 첨부로 처리하고, 글자는 원래대로 붙여넣는다.
    private func installImagePasteMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 한글 입력 중에는 글자가 "ㅍ" 로 오므로 글자 대신 물리 키 위치(V = 9)로 판단한다.
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard flags == .command, event.keyCode == 9,
                  ImageLoader.pasteboardHasImage() else { return event }
            NotificationCenter.default.post(name: .kimBiseoPasteImages, object: nil)
            return nil
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()
        installImagePasteMonitor()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bubble.left.and.text.bubble.right", accessibilityDescription: "김비서")
            button.action = #selector(togglePopover)
            button.target = self
        }

        panel = KimBiseoPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 620),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        panel.title = "김비서"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let hosting = NSHostingController(rootView: RootView(model: model))
        hosting.sizingOptions = [.minSize]          // 창 크기는 사용자가 정하고, 최소 크기만 화면이 정한다
        panel.contentViewController = hosting
        panel.contentMinSize = NSSize(width: 420, height: 420)
        if !panel.setFrameUsingName("KimBiseoMain") { placeUnderStatusItem() }
        panel.setFrameAutosaveName("KimBiseoMain")

        hotkeyWatch = model.$settings.map(\.hotkey).removeDuplicates().sink { [weak self] key in
            self?.hotkey.register(key) { self?.togglePopover() }
        }
        notifier = Notifier { [weak self] in
            self?.model.selected = .chat
            self?.showPopover()
        }
        reminderPanel = ReminderPanelController(center: reminders) { [weak self] in
            self?.model.selected = .chat
            self?.showPopover()
        }
        reminders.start()
        reminderPanel.refresh()
        triggers = TriggerWatcher(model: model, notifier: notifier, reminders: reminders)
        scheduler = AlarmScheduler(model: model, notifier: notifier, reminders: reminders, triggers: triggers)
        scheduler.start()
        triggers.start()
    }

    @objc private func togglePopover() {
        panel.isVisible && panel.isKeyWindow ? panel.orderOut(nil) : showPopover()
    }

    private func showPopover() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// 처음 열 때는 메뉴바 아이콘 바로 아래에 둔다. 이후에는 사용자가 옮긴 위치를 쓴다.
    private func placeUnderStatusItem() {
        guard let button = statusItem.button, let window = button.window else { panel.center(); return }
        let iconFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: iconFrame.midX - size.width / 2, y: iconFrame.minY - size.height - 6))
    }
}

extension Notification.Name {
    static let kimBiseoPasteImages = Notification.Name("kimBiseoPasteImages")
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
