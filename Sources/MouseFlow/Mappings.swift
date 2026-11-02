import AppKit

struct Shortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt64

    var flags: CGEventFlags { CGEventFlags(rawValue: modifiers) }

    var display: String {
        var text = ""
        if flags.contains(.maskControl) { text += "⌃" }
        if flags.contains(.maskAlternate) { text += "⌥" }
        if flags.contains(.maskShift) { text += "⇧" }
        if flags.contains(.maskCommand) { text += "⌘" }
        return text + (Self.keyNames[keyCode] ?? "Key \(keyCode)")
    }

    // ANSI layout virtual key codes; enough to label any shortcut a mouse button is likely to send.
    private static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
        12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
        22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
        32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦",
        115: "Home", 119: "End", 116: "PgUp", 121: "PgDn",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}

enum SystemAction: String, CaseIterable, Codable {
    case showDesktop, previousSpace, nextSpace, missionControl, appWindows

    var title: String {
        switch self {
        case .showDesktop: tr("Show Desktop", "Hiện Desktop")
        case .previousSpace: tr("Desktop on the left", "Desktop bên trái")
        case .nextSpace: tr("Desktop on the right", "Desktop bên phải")
        case .missionControl: "Mission Control"
        case .appWindows: tr("App windows", "Cửa sổ của app")
        }
    }

    // IDs and factory defaults of the matching entries in System Settings → Keyboard Shortcuts.
    private var hotkey: (id: Int, fallback: Shortcut) {
        let controlFn = CGEventFlags([.maskControl, .maskSecondaryFn]).rawValue
        switch self {
        case .missionControl: return (32, Shortcut(keyCode: 126, modifiers: controlFn))
        case .appWindows: return (33, Shortcut(keyCode: 125, modifiers: controlFn))
        case .showDesktop: return (36, Shortcut(keyCode: 103, modifiers: CGEventFlags.maskSecondaryFn.rawValue))
        case .previousSpace: return (79, Shortcut(keyCode: 123, modifiers: controlFn))
        case .nextSpace: return (81, Shortcut(keyCode: 124, modifiers: controlFn))
        }
    }

    // Read at send time so a shortcut the user rebinds in System Settings keeps working.
    var shortcut: Shortcut {
        let domain = "com.apple.symbolichotkeys" as CFString
        CFPreferencesAppSynchronize(domain)
        let hotkeys = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any]
        let entry = hotkeys?[String(hotkey.id)] as? [String: Any]
        let parameters = (entry?["value"] as? [String: Any])?["parameters"] as? [Int]
        guard let parameters, parameters.count == 3 else { return hotkey.fallback }
        return Shortcut(keyCode: UInt16(parameters[1]), modifiers: UInt64(parameters[2]))
    }
}

enum MouseAction: Codable, Equatable {
    case shortcut(Shortcut)
    case system(SystemAction)
    // Keeps the button's own behaviour in an app even when "every app" maps it.
    case native

    var title: String {
        switch self {
        case .shortcut(let shortcut): shortcut.display
        case .system(let action): action.title
        case .native: tr("Keep native behaviour", "Giữ chức năng gốc")
        }
    }

    private enum CodingKeys: String, CodingKey { case system, native }

    // Older builds stored a bare Shortcut, so that shape still decodes as one.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let action = try container.decodeIfPresent(SystemAction.self, forKey: .system) {
            self = .system(action)
        } else if try container.decodeIfPresent(Bool.self, forKey: .native) == true {
            self = .native
        } else {
            self = .shortcut(try Shortcut(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .shortcut(let shortcut):
            try shortcut.encode(to: encoder)
        case .system(let action):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(action, forKey: .system)
        case .native:
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(true, forKey: .native)
        }
    }
}

struct AppMapping: Codable, Equatable {
    var name: String
    var buttons: [String: MouseAction] = [:]
}

struct ButtonMappings: Codable, Equatable {
    var defaults: [String: MouseAction] = [:]
    var apps: [String: AppMapping] = [:]
}

final class MappingStore: ObservableObject {
    private static let key = "buttonMappings"

    @Published var mappings: ButtonMappings {
        didSet {
            if let data = try? JSONEncoder().encode(mappings) {
                UserDefaults.standard.set(data, forKey: Self.key)
            }
        }
    }

    init() {
        let data = UserDefaults.standard.data(forKey: Self.key)
        mappings = data.flatMap { try? JSONDecoder().decode(ButtonMappings.self, from: $0) } ?? ButtonMappings()
    }

    // An app's own mapping wins over the default; nil means the button keeps its normal behaviour.
    func shortcut(button: Int, bundleID: String?) -> Shortcut? {
        let key = String(button)
        let action = bundleID.flatMap { mappings.apps[$0]?.buttons[key] } ?? mappings.defaults[key]
        switch action {
        case .shortcut(let shortcut): return shortcut
        case .system(let system): return system.shortcut
        case .native, nil: return nil
        }
    }
}
