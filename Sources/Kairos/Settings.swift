import AppKit
import Carbon.HIToolbox
import Observation
import ServiceManagement

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32  // Carbon modifier mask
    var key: String        // display name of the key, e.g. "V"

    static let `default` = Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(optionKey), key: "V")

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// Builds a shortcut from a key press. Returns nil when no ⌘/⌥/⌃ is held,
    /// so plain typing can never be hijacked.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        guard mods & UInt32(cmdKey | optionKey | controlKey) != 0 else { return nil }

        keyCode = UInt32(event.keyCode)
        modifiers = mods
        switch Int(event.keyCode) {
        case kVK_Space: key = "Space"
        case kVK_Return: key = "↩"
        case kVK_Tab: key = "⇥"
        default:
            // ⌥ changes the typed character (⌥V → √), so ask for the bare key.
            key = (event.characters(byApplyingModifiers: []) ?? "?").uppercased()
        }
    }

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + key
    }
}

enum PopupPosition: String, CaseIterable, Identifiable {
    case caret, center, mouse

    var id: Self { self }

    var title: String {
        switch self {
        case .caret: "Text cursor"
        case .center: "Screen center"
        case .mouse: "Mouse pointer"
        }
    }
}

@MainActor
@Observable
final class Settings {
    static let shared = Settings()

    @ObservationIgnored private let defaults = UserDefaults.standard

    var maxItems: Int {
        didSet { defaults.set(maxItems, forKey: "maxItems") }
    }

    var shortcut: Shortcut {
        didSet { defaults.set(try? JSONEncoder().encode(shortcut), forKey: "shortcut") }
    }

    var position: PopupPosition {
        didSet { defaults.set(position.rawValue, forKey: "position") }
    }

    var hasCompletedSetup: Bool {
        didSet { defaults.set(hasCompletedSetup, forKey: "hasCompletedSetup") }
    }

    private(set) var launchAtLogin: Bool

    private init() {
        maxItems = defaults.object(forKey: "maxItems") as? Int ?? 30
        shortcut = defaults.data(forKey: "shortcut").flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .default
        position = defaults.string(forKey: "position").flatMap(PopupPosition.init) ?? .mouse
        hasCompletedSetup = defaults.bool(forKey: "hasCompletedSetup")
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Kairos: launch at login change failed: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
