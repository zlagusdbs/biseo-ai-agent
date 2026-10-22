import Carbon
import Foundation
import KimBiseoCore

/// 전역 단축키. macOS 단축키 등록 기능이라 손쉬운 사용 권한이 필요 없다. 설정에서 바꾸면 다시 등록한다.
final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: () -> Void = {}

    func register(_ hotkey: Hotkey, action: @escaping () -> Void) {
        self.action = action
        if handlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let me = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { manager.action() }
                return noErr
            }, 1, &spec, me, &handlerRef)
        }
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        let id = EventHotKeyID(signature: OSType(0x4B49_4D42), id: 1) // "KIMB"
        RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
