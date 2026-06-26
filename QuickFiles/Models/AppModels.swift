import Carbon
import Foundation

struct FileItem: Identifiable, Hashable {
    let id: String
    let url: URL
    let displayName: String
    let parentPath: String
    let modifiedAt: Date?
    let createdAt: Date?
    let addedAt: Date?
    let metadataChangedAt: Date?
    let kind: FileItemKind

    init(
        url: URL,
        modifiedAt: Date?,
        createdAt: Date?,
        addedAt: Date? = nil,
        metadataChangedAt: Date? = nil,
        kind: FileItemKind
    ) {
        self.url = url
        self.id = url.path
        self.displayName = url.lastPathComponent
        self.parentPath = url.deletingLastPathComponent().path
        self.modifiedAt = modifiedAt
        self.createdAt = createdAt
        self.addedAt = addedAt
        self.metadataChangedAt = metadataChangedAt
        self.kind = kind
    }

    var activityAt: Date? {
        [modifiedAt, createdAt, addedAt, metadataChangedAt].compactMap { $0 }.max()
    }
}

enum FileItemKind: String, Codable {
    case recent
    case bookmark
}

struct StoredBookmark: Identifiable, Codable, Hashable {
    let id: UUID
    var url: URL
    var bookmarkData: Data?

    init(id: UUID = UUID(), url: URL, bookmarkData: Data? = nil) {
        self.id = id
        self.url = url
        self.bookmarkData = bookmarkData
    }
}

struct FolderRule: Identifiable, Codable, Hashable {
    let id: UUID
    var url: URL
    var bookmarkData: Data?

    init(id: UUID = UUID(), url: URL, bookmarkData: Data? = nil) {
        self.id = id
        self.url = url
        self.bookmarkData = bookmarkData
    }
}

struct HotKeyDefinition: Codable, Hashable {
    var keyCode: UInt32
    var modifierFlags: UInt32

    static let defaultValue = HotKeyDefinition(
        keyCode: UInt32(kVK_ANSI_Slash),
        modifierFlags: UInt32(cmdKey | shiftKey)
    )

    static let legacyOptionSpace = HotKeyDefinition(
        keyCode: UInt32(kVK_Space),
        modifierFlags: UInt32(optionKey)
    )

    var hasModifier: Bool {
        modifierFlags & UInt32(controlKey | optionKey | shiftKey | cmdKey) != 0
    }

    var displayText: String {
        var parts: [String] = []
        if modifierFlags & UInt32(controlKey) != 0 { parts.append("Control") }
        if modifierFlags & UInt32(optionKey) != 0 { parts.append("Option") }
        if modifierFlags & UInt32(shiftKey) != 0 { parts.append("Shift") }
        if modifierFlags & UInt32(cmdKey) != 0 { parts.append("Command") }
        parts.append(HotKeyKey.label(for: keyCode))
        return parts.joined(separator: " + ")
    }
}

enum HotKeyKey: String, CaseIterable, Identifiable {
    case space = "Space"
    case returnKey = "Return"
    case tab = "Tab"
    case slash = "/"
    case period = "."
    case comma = ","
    case f1 = "F1"
    case f2 = "F2"
    case f3 = "F3"
    case f4 = "F4"
    case f5 = "F5"
    case f6 = "F6"
    case f7 = "F7"
    case f8 = "F8"
    case f9 = "F9"
    case f10 = "F10"
    case f11 = "F11"
    case f12 = "F12"

    var id: UInt32 { keyCode }
    var label: String { rawValue }

    init?(keyCode: UInt32) {
        guard let match = Self.allCases.first(where: { $0.keyCode == keyCode }) else { return nil }
        self = match
    }

    static func label(for keyCode: UInt32) -> String {
        if let key = HotKeyKey(keyCode: keyCode) {
            return key.label
        }

        let specialKeys: [UInt32: String] = [
            UInt32(kVK_Escape): "Escape",
            UInt32(kVK_Delete): "Delete",
            UInt32(kVK_ForwardDelete): "Forward Delete",
            UInt32(kVK_Home): "Home",
            UInt32(kVK_End): "End",
            UInt32(kVK_PageUp): "Page Up",
            UInt32(kVK_PageDown): "Page Down",
            UInt32(kVK_LeftArrow): "Left Arrow",
            UInt32(kVK_RightArrow): "Right Arrow",
            UInt32(kVK_UpArrow): "Up Arrow",
            UInt32(kVK_DownArrow): "Down Arrow",
            UInt32(kVK_ANSI_0): "0",
            UInt32(kVK_ANSI_1): "1",
            UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3",
            UInt32(kVK_ANSI_4): "4",
            UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6",
            UInt32(kVK_ANSI_7): "7",
            UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_ANSI_A): "A",
            UInt32(kVK_ANSI_B): "B",
            UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D",
            UInt32(kVK_ANSI_E): "E",
            UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G",
            UInt32(kVK_ANSI_H): "H",
            UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J",
            UInt32(kVK_ANSI_K): "K",
            UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M",
            UInt32(kVK_ANSI_N): "N",
            UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P",
            UInt32(kVK_ANSI_Q): "Q",
            UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S",
            UInt32(kVK_ANSI_T): "T",
            UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V",
            UInt32(kVK_ANSI_W): "W",
            UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y",
            UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_Minus): "-",
            UInt32(kVK_ANSI_Equal): "=",
            UInt32(kVK_ANSI_LeftBracket): "[",
            UInt32(kVK_ANSI_RightBracket): "]",
            UInt32(kVK_ANSI_Backslash): "\\",
            UInt32(kVK_ANSI_Semicolon): ";",
            UInt32(kVK_ANSI_Quote): "'",
            UInt32(kVK_ANSI_Grave): "`"
        ]

        return specialKeys[keyCode] ?? "Key \(keyCode)"
    }
    var keyCode: UInt32 {
        switch self {
        case .space: return UInt32(kVK_Space)
        case .returnKey: return UInt32(kVK_Return)
        case .tab: return UInt32(kVK_Tab)
        case .slash: return UInt32(kVK_ANSI_Slash)
        case .period: return UInt32(kVK_ANSI_Period)
        case .comma: return UInt32(kVK_ANSI_Comma)
        case .f1: return UInt32(kVK_F1)
        case .f2: return UInt32(kVK_F2)
        case .f3: return UInt32(kVK_F3)
        case .f4: return UInt32(kVK_F4)
        case .f5: return UInt32(kVK_F5)
        case .f6: return UInt32(kVK_F6)
        case .f7: return UInt32(kVK_F7)
        case .f8: return UInt32(kVK_F8)
        case .f9: return UInt32(kVK_F9)
        case .f10: return UInt32(kVK_F10)
        case .f11: return UInt32(kVK_F11)
        case .f12: return UInt32(kVK_F12)
        }
    }
}
