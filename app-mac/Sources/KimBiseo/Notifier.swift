import Foundation
import UserNotifications

/// Mac 알림. 알림을 누르면 onOpen 이 불린다. .app 으로 묶어 실행할 때만 동작한다(번들 ID 필요).
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let onOpen: () -> Void
    /// 알림 메뉴의 「Mac 알림」 체크. 꺼져 있으면 보내지 않는다.
    var isEnabled: () -> Bool = { true }
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    init(onOpen: @escaping () -> Void) {
        self.onOpen = onOpen
        super.init()
        center?.delegate = self
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func send(title: String, body: String) {
        guard isEnabled() else { return }
        guard let center else {
            print("[알림] \(title)\n\(body)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { self.onOpen() }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
