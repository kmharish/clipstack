import AppKit
import Combine
import os.log

/// Application delegate. Wires together all major components and acts as
/// the single composition root for the app.
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Components

    private var clipboardViewModel: ClipboardViewModel!
    private var menuBarController: MenuBarController!
    private let logger = Logger(subsystem: "com.clipstack.ClipStack", category: "AppDelegate")

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("ClipStack launching…")

        // 1. App icon — LSUIElement apps don't load it automatically,
        //    so set it explicitly so the About panel displays it correctly.
        if let icon = NSImage(named: "AppIconImage") {
            NSApp.applicationIconImage = icon
        }

        // 2. Core Data persistence (must come first)
        _ = PersistenceController.shared

        // 2. ViewModel (starts clipboard polling)
        clipboardViewModel = ClipboardViewModel()

        // 3. Menu bar UI
        menuBarController = MenuBarController(viewModel: clipboardViewModel)

        // 4. Global keyboard shortcuts (CGEventTap)
        KeyboardShortcutManager.shared.setup(viewModel: clipboardViewModel)

        // 5. Sync Login Item state with preferences
        syncLoginItemState()

        logger.info("ClipStack launched successfully.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Persist any unsaved Core Data changes
        PersistenceController.shared.save()
        // Remove the event tap cleanly
        KeyboardShortcutManager.shared.teardown()
        logger.info("ClipStack terminating.")
    }

    // MARK: - Private Helpers

    private func syncLoginItemState() {
        let shouldLaunchAtLogin = PreferencesManager.shared.launchAtLogin
        let isRegistered        = LoginItemManager.isEnabled
        guard shouldLaunchAtLogin != isRegistered else { return }
        LoginItemManager.setEnabled(shouldLaunchAtLogin)
    }
}
