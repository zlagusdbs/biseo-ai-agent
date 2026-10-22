import Foundation

/// 전역 단축키. modifiers 는 Carbon 값(cmdKey 256, shiftKey 512, optionKey 2048, controlKey 4096).
public struct Hotkey: Codable, Equatable {
    public static let command: UInt32 = 256, shift: UInt32 = 512, option: UInt32 = 2048, control: UInt32 = 4096
    public static let `default` = Hotkey(keyCode: 49, modifiers: control | option | shift | command)   // ⇧⌃⌥⌘ Space

    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Shift 만으로는 글자 입력과 겹치므로 ⌘·⌃·⌥ 중 하나는 있어야 한다.
    public var isValid: Bool { modifiers & (Self.command | Self.control | Self.option) != 0 }

    /// Mac 표기 순서: ⌃⌥⇧⌘ + 키
    public var display: String {
        var text = ""
        if modifiers & Self.control != 0 { text += "⌃" }
        if modifiers & Self.option != 0 { text += "⌥" }
        if modifiers & Self.shift != 0 { text += "⇧" }
        if modifiers & Self.command != 0 { text += "⌘" }
        return text + " " + (Self.keyNames[keyCode] ?? "키 \(keyCode)")
    }

    static let keyNames: [UInt32: String] = {
        var names: [UInt32: String] = [49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc",
                                       123: "←", 124: "→", 125: "↓", 126: "↑"]
        let letters: [(UInt32, String)] = [(0, "A"), (11, "B"), (8, "C"), (2, "D"), (14, "E"), (3, "F"), (5, "G"), (4, "H"),
                                           (34, "I"), (38, "J"), (40, "K"), (37, "L"), (46, "M"), (45, "N"), (31, "O"),
                                           (35, "P"), (12, "Q"), (15, "R"), (1, "S"), (17, "T"), (32, "U"), (9, "V"),
                                           (13, "W"), (7, "X"), (16, "Y"), (6, "Z")]
        let digits: [(UInt32, String)] = [(29, "0"), (18, "1"), (19, "2"), (20, "3"), (21, "4"), (23, "5"), (22, "6"),
                                          (26, "7"), (28, "8"), (25, "9")]
        let symbols: [(UInt32, String)] = [(27, "-"), (24, "="), (33, "["), (30, "]"), (42, "\\\\"), (41, ";"), (39, "'"),
                                           (43, ","), (47, "."), (44, "/"), (50, "`")]
        let functions: [(UInt32, String)] = [(122, "F1"), (120, "F2"), (99, "F3"), (118, "F4"), (96, "F5"), (97, "F6"),
                                             (98, "F7"), (100, "F8"), (101, "F9"), (109, "F10"), (103, "F11"), (111, "F12")]
        for (code, name) in letters + digits + symbols + functions { names[code] = name }
        return names
    }()
}
