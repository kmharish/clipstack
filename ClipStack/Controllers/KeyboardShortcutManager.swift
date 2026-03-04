import AppKit
import os.log

/// Monitors global keyboard events to intercept CMD+V and CMD+Shift+V,
/// swapping the clipboard content before the event reaches the target app.
///
/// Uses `NSEvent.addGlobalMonitorForEvents` which works inside the
/// App Sandbox (unlike CGEventTap) and requires Accessibility permission.
final class KeyboardShortcutManager {

    // MARK: - Shared Instance

    static let shared = KeyboardShortcutManager()

    // MARK: - Private State

    private var monitor: Any?
    private weak var viewModel: ClipboardViewModel?
    private let logger = Logger(subsystem: "com.clipstack.ClipStack", category: "KeyboardShortcuts")

    private init() {}

    // MARK: - Setup

    func setup(viewModel: ClipboardViewModel) {
        self.viewModel = viewModel

        guard checkAccessibilityPermission() else {
            requestAccessibilityPermission()
            return
        }
        installMonitor()
    }

    // MARK: - Accessibility Permission

    private func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func requestAccessibilityPermission() {
        logger.warning("Accessibility permission not granted – requesting.")

        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
        ClipStack needs Accessibility access to detect when you press CMD+V \
        and deliver items from your clipboard history.

        Please grant access in System Settings → Privacy & Security → Accessibility, \
        then relaunch ClipStack.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .warning

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let promptOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(promptOptions)
        }
    }

    // MARK: - Monitor Installation

    private func installMonitor() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleEvent(event)
        }
        logger.info("Global keyboard monitor installed.")
    }

    // MARK: - Event Handling

    private func handleEvent(_ event: NSEvent) {
        guard let vm = viewModel, !vm.stack.isEmpty else { return }

        let cmdOnly   = event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command
        let cmdShift  = event.modifierFlags.intersection([.command, .shift, .option, .control]) == [.command, .shift]

        // CMD+V → paste selected item
        if event.keyCode == 0x09 && cmdOnly {
            vm.prepareSelectedForPaste()
            logger.debug("CMD+V: swapped clipboard to selected item.")
            return
        }

        // CMD+Shift+V → paste most recent item
        if event.keyCode == 0x09 && cmdShift {
            vm.prepareMostRecentForPaste()
            logger.debug("CMD+Shift+V: swapped clipboard to most recent item.")
        }
    }

    // MARK: - Teardown

    func teardown() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        logger.info("Global keyboard monitor removed.")
    }
}
