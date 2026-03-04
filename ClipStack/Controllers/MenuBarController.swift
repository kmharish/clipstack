import AppKit
import Combine
import os.log

/// Owns the `NSStatusItem` (menu bar icon) and rebuilds the dropdown
/// `NSMenu` whenever the clipboard stack or selection changes.
final class MenuBarController {

    // MARK: - Private Properties

    private let statusItem: NSStatusItem
    private let viewModel: ClipboardViewModel
    private let preferences: PreferencesManager
    private var cancellables = Set<AnyCancellable>()
    private var preferencesWindowController: PreferencesWindowController?
    private let logger = Logger(subsystem: "com.clipstack.ClipStack", category: "MenuBar")

    // MARK: - Init

    init(viewModel: ClipboardViewModel, preferences: PreferencesManager = .shared) {
        self.viewModel   = viewModel
        self.preferences = preferences
        self.statusItem  = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        configureStatusButton()
        buildMenu()
        subscribeToViewModelChanges()
    }

    // MARK: - Status Button

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        // Load from asset catalog; template-rendering-intent is set in Contents.json
        // so macOS will auto-tint for light/dark menu bar.
        if let image = NSImage(named: "MenuBarIcon") {
            button.image = image
        } else {
            button.title = "📋"
        }
        button.toolTip = "ClipStack – Clipboard Manager"
        button.setAccessibilityLabel("ClipStack menu")
    }

    // MARK: - Reactive Rebuild

    private func subscribeToViewModelChanges() {
        viewModel.$stack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.buildMenu() }
            .store(in: &cancellables)

        viewModel.$selectedIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.buildMenu() }
            .store(in: &cancellables)
    }

    // MARK: - Menu Construction

    /// Rebuilds the entire `NSMenu` from the current stack state.
    func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Header
        let headerItem = NSMenuItem()
        headerItem.title = "ClipStack  (\(viewModel.stack.count) items)"
        headerItem.isEnabled = false
        headerItem.setAccessibilityLabel("ClipStack header")
        menu.addItem(headerItem)
        menu.addItem(.separator())

        // Clipboard items
        if viewModel.stack.isEmpty {
            let emptyItem = NSMenuItem(title: "No items copied yet", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for (index, item) in viewModel.stack.enumerated() {
                menu.addItem(makeClipItem(item, at: index))
            }
        }

        menu.addItem(.separator())

        // Actions
        menu.addItem(makeClearHistoryItem())
        menu.addItem(makePreferencesItem())
        menu.addItem(makeAboutItem())
        menu.addItem(.separator())
        menu.addItem(makeQuitItem())

        statusItem.menu = menu
    }

    // MARK: - Menu Item Factories

    private func makeClipItem(_ item: ClipItem, at index: Int) -> NSMenuItem {
        let displayText  = item.displayContent
        let menuItem     = NSMenuItem(title: displayText, action: #selector(clipItemSelected(_:)), keyEquivalent: "")
        menuItem.target  = self
        menuItem.tag     = index
        menuItem.isEnabled = true

        // Keyboard hint: 1–9 for first 9 items
        if index < 9 {
            menuItem.keyEquivalent = "\(index + 1)"
            menuItem.keyEquivalentModifierMask = [.command]
        }

        // Checkmark for selected item
        menuItem.state = (index == viewModel.selectedIndex) ? .on : .off

        // Type icon
        if preferences.showTypeIcons {
            let symbolName = item.symbolName
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: item.contentType) {
                image.isTemplate = true
                menuItem.image = image
            }
        }

        // VoiceOver
        menuItem.setAccessibilityLabel("Clipboard item \(index + 1): \(displayText)")

        // Right-click / contextual submenu for delete
        let submenu = NSMenu()
        let deleteItem = NSMenuItem(
            title: "Remove from Stack",
            action: #selector(deleteClipItem(_:)),
            keyEquivalent: ""
        )
        deleteItem.target = self
        deleteItem.tag    = index
        submenu.addItem(deleteItem)
        menuItem.submenu  = submenu

        return menuItem
    }

    private func makeClearHistoryItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "k")
        item.keyEquivalentModifierMask = [.command, .shift]
        item.target = self
        return item
    }

    private func makePreferencesItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        item.keyEquivalentModifierMask = .command
        item.target = self
        return item
    }

    private func makeAboutItem() -> NSMenuItem {
        let item = NSMenuItem(title: "About ClipStack", action: #selector(openAbout), keyEquivalent: "")
        item.target = self
        return item
    }

    private func makeQuitItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Quit ClipStack", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.keyEquivalentModifierMask = .command
        return item
    }

    // MARK: - Actions

    @objc private func clipItemSelected(_ sender: NSMenuItem) {
        let index = sender.tag
        viewModel.select(at: index)
        // Immediately paste the selected item into the active app
        if let content = viewModel.prepareSelectedForPaste() {
            paste(content)
        }
        logger.debug("User selected item at index \(index) from menu.")
    }

    @objc private func deleteClipItem(_ sender: NSMenuItem) {
        viewModel.remove(at: sender.tag)
    }

    @objc private func openAbout() {
        NSApp.activate(ignoringOtherApps: true)
        var options: [NSApplication.AboutPanelOptionKey: Any] = [:]
        if let icon = NSImage(named: "AppIconImage") {
            options[.applicationIcon] = icon
        }
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear Clipboard History?"
        alert.informativeText = "This will permanently remove all \(viewModel.stack.count) items from ClipStack."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        viewModel.clearAll()
    }

    @objc private func openPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(viewModel: viewModel)
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindowController?.showWindow(nil)
        preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Paste Helper

    /// Writes `content` to the clipboard and synthesises CMD+V in the
    /// previously active application.
    private func paste(_ content: String) {
        // The clipboard was already updated by prepareSelectedForPaste().
        // Now simulate CMD+V so the frontmost app receives the paste.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let src = CGEventSource(stateID: .hidSystemState)
            // Key-down  V  with command
            if let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true) {
                down.flags = .maskCommand
                down.post(tap: .cghidEventTap)
            }
            // Key-up V
            if let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false) {
                up.flags = .maskCommand
                up.post(tap: .cghidEventTap)
            }
        }
    }
}
