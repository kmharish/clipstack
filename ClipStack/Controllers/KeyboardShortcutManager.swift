import Cocoa
import Carbon
import os.log

/// Installs a system-wide `CGEventTap` that intercepts configured keyboard
/// shortcuts and routes them through `ClipboardViewModel`.
///
/// **Requires Accessibility permission.** If the permission is not granted,
/// the manager presents a system alert and opens System Settings.
final class KeyboardShortcutManager {

    // MARK: - Shared Instance

    static let shared = KeyboardShortcutManager()

    // MARK: - Private State

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private weak var viewModel: ClipboardViewModel?
    private let preferences = PreferencesManager.shared
    private let logger = Logger(subsystem: "com.clipstack.ClipStack", category: "KeyboardShortcuts")

    private init() {}

    // MARK: - Setup

    func setup(viewModel: ClipboardViewModel) {
        self.viewModel = viewModel

        guard checkAccessibilityPermission() else {
            requestAccessibilityPermission()
            return
        }
        installEventTap()
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
        ClipStack needs Accessibility access to intercept CMD+V and route \
        items from your clipboard history.

        Please grant access in System Settings → Privacy & Security → Accessibility, \
        then relaunch ClipStack.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .warning

        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == .alertFirstButtonReturn {
            // Prompt the system dialog (this sets the "prompt" flag to true)
            let promptOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(promptOptions)
        }
    }

    // MARK: - Event Tap Installation

    private func installEventTap() {
        // We intercept keyDown events at the HID (hardware) level so we see them
        // regardless of which application is focused.
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        // The C callback is a closure captured via `Unmanaged` pointer to `self`.
        let callback: CGEventTapCallBack = { _, type, event, refcon -> Unmanaged<CGEvent>? in
            guard type == .keyDown, let refcon = refcon else {
                return Unmanaged.passRetained(event)
            }
            let manager = Unmanaged<KeyboardShortcutManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handleEvent(event)
        }

        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap:         .cghidEventTap,
            place:       .headInsertEventTap,
            options:     .defaultTap,
            eventsOfInterest: eventMask,
            callback:    callback,
            userInfo:    selfPtr
        )

        guard let tap = eventTap else {
            logger.error("Failed to create CGEventTap – accessibility permission may have been revoked.")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        logger.info("CGEventTap installed successfully.")
    }

    // MARK: - Event Handling

    /// Returns `nil` to consume the event (prevent default behaviour),
    /// or `Unmanaged.passRetained(event)` to let it through unchanged.
    private func handleEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags   = event.flags

        let commandOnly   = flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl]) == .maskCommand
        let commandShift  = flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl]) == [.maskCommand, .maskShift]

        // CMD+V → paste selected item
        if keyCode == 0x09 && commandOnly {
            return handlePasteSelected()
        }

        // CMD+Shift+V → paste most recent item
        if keyCode == 0x09 && commandShift {
            return handlePasteMostRecent()
        }

        return Unmanaged.passRetained(event)
    }

    // MARK: - Handlers

    private func handlePasteSelected() -> Unmanaged<CGEvent>? {
        guard let vm = viewModel else { return nil }

        if vm.stack.isEmpty {
            // No items – fall through to normal CMD+V behaviour
            return nil
        }

        // Write the selected item to the clipboard, then let a NEW CMD+V event
        // through (we consume this one to avoid infinite recursion).
        vm.prepareSelectedForPaste()
        dispatchNativePaste()
        logger.debug("Paste selected item via CMD+V intercept.")

        // Consume this event
        return nil
    }

    private func handlePasteMostRecent() -> Unmanaged<CGEvent>? {
        guard let vm = viewModel else { return nil }

        vm.prepareMostRecentForPaste()
        dispatchNativePaste()
        logger.debug("Paste most recent item via CMD+Shift+V.")

        return nil
    }

    // MARK: - Native Paste Dispatch

    /// Posts a raw CMD+V event that bypasses our tap (because we temporarily
    /// disable the tap before sending and re-enable it after).
    private func dispatchNativePaste() {
        guard let tap = eventTap else { return }

        // Disable tap so the event we're about to create doesn't recurse.
        CGEvent.tapEnable(tap: tap, enable: false)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            let src = CGEventSource(stateID: .hidSystemState)
            if let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true) {
                down.flags = .maskCommand
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false) {
                up.flags = .maskCommand
                up.post(tap: .cghidEventTap)
            }
            // Re-enable tap
            if let tap = self?.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
    }

    // MARK: - Teardown

    func teardown() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        logger.info("CGEventTap removed.")
    }
}
