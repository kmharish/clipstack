import AppKit
import Combine

/// Strongly-typed wrapper around `UserDefaults` for all ClipStack preferences.
///
/// Publishes changes via Combine so UI components can reactively update.
final class PreferencesManager: ObservableObject {

    // MARK: - Shared Instance

    static let shared = PreferencesManager()

    // MARK: - UserDefaults Keys

    private enum Key: String {
        case maxStackSize          = "maxStackSize"
        case launchAtLogin         = "launchAtLogin"
        case pasteSelectedKey      = "pasteSelectedKey"
        case pasteSelectedMods     = "pasteSelectedMods"
        case pasteMostRecentKey    = "pasteMostRecentKey"
        case pasteMostRecentMods   = "pasteMostRecentMods"
        case showTypeIcons         = "showTypeIcons"
        case trimWhitespace        = "trimWhitespace"
        case ignoreDuplicates      = "ignoreDuplicates"
    }

    // MARK: - Defaults

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // All stored properties must be initialized before calling self methods.
        // Inline defaults on the @Published vars satisfy phase 1;
        // we overwrite them with persisted values below (didSet is NOT called in designated init).
        registerDefaults()
        self.maxStackSize  = defaults.integer(forKey: Key.maxStackSize.rawValue)
        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin.rawValue)
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Key.maxStackSize.rawValue:        10,
            Key.launchAtLogin.rawValue:       false,
            // CMD+V  (keyCode 9, flags: command)
            Key.pasteSelectedKey.rawValue:    9,
            Key.pasteSelectedMods.rawValue:   UInt64(NSEvent.ModifierFlags.command.rawValue),
            // CMD+Shift+V  (keyCode 9, flags: command+shift)
            Key.pasteMostRecentKey.rawValue:  9,
            Key.pasteMostRecentMods.rawValue: UInt64((NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)),
            Key.showTypeIcons.rawValue:       true,
            Key.trimWhitespace.rawValue:      true,
            Key.ignoreDuplicates.rawValue:    true,
        ])
    }

    // MARK: - Preferences

    /// Maximum number of items the stack holds before evicting the oldest.
    @Published var maxStackSize: Int = 10 {
        didSet { defaults.set(maxStackSize, forKey: Key.maxStackSize.rawValue) }
    }

    /// Whether to add ClipStack as a Login Item.
    @Published var launchAtLogin: Bool = false {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin.rawValue) }
    }

    /// Key code for the "paste selected item" shortcut (default: CMD+V).
    var pasteSelectedKeyCode: UInt16 {
        get { UInt16(defaults.integer(forKey: Key.pasteSelectedKey.rawValue)) }
        set { defaults.set(newValue, forKey: Key.pasteSelectedKey.rawValue) }
    }

    /// Modifier flags for the "paste selected item" shortcut.
    var pasteSelectedModifiers: NSEvent.ModifierFlags {
        get {
            let raw = UInt(defaults.integer(forKey: Key.pasteSelectedMods.rawValue))
            return NSEvent.ModifierFlags(rawValue: raw)
        }
        set { defaults.set(newValue.rawValue, forKey: Key.pasteSelectedMods.rawValue) }
    }

    /// Key code for the "paste most recent item" shortcut (default: CMD+Shift+V).
    var pasteMostRecentKeyCode: UInt16 {
        get { UInt16(defaults.integer(forKey: Key.pasteMostRecentKey.rawValue)) }
        set { defaults.set(newValue, forKey: Key.pasteMostRecentKey.rawValue) }
    }

    /// Modifier flags for the "paste most recent item" shortcut.
    var pasteMostRecentModifiers: NSEvent.ModifierFlags {
        get {
            let raw = UInt(defaults.integer(forKey: Key.pasteMostRecentMods.rawValue))
            return NSEvent.ModifierFlags(rawValue: raw)
        }
        set { defaults.set(newValue.rawValue, forKey: Key.pasteMostRecentMods.rawValue) }
    }

    /// Whether to show content-type icons in the menu.
    var showTypeIcons: Bool {
        get { defaults.bool(forKey: Key.showTypeIcons.rawValue) }
        set { defaults.set(newValue, forKey: Key.showTypeIcons.rawValue) }
    }

    /// Whether to strip leading/trailing whitespace before storing.
    var trimWhitespace: Bool {
        get { defaults.bool(forKey: Key.trimWhitespace.rawValue) }
        set { defaults.set(newValue, forKey: Key.trimWhitespace.rawValue) }
    }

    /// Whether to skip storing an item that is already in the stack.
    var ignoreDuplicates: Bool {
        get { defaults.bool(forKey: Key.ignoreDuplicates.rawValue) }
        set { defaults.set(newValue, forKey: Key.ignoreDuplicates.rawValue) }
    }

}
