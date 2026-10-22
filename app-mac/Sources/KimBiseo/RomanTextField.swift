import AppKit
import SwiftUI

/// 입력하는 동안 영문 입력만 허용하는 텍스트 칸. 한글 입력 상태에서 보안 입력 칸에 숫자만 들어가는 문제를 막는다.
struct RomanTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var secure = false
    var onSubmit: () -> Void = {}

    func makeNSView(context: Context) -> NSTextField {
        let field: NSTextField = secure ? RomanSecureField() : RomanPlainField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RomanTextField
        init(_ parent: RomanTextField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        @objc func submit() { parent.onSubmit() }
    }
}

private func allowRomanOnly(_ field: NSTextField) {
    field.currentEditor()?.inputContext?.allowedInputSourceLocales = [NSAllRomanInputSourcesLocaleIdentifier]
}

private final class RomanPlainField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        allowRomanOnly(self)
        return ok
    }
}

private final class RomanSecureField: NSSecureTextField {
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        allowRomanOnly(self)
        return ok
    }
}
