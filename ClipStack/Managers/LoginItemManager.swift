import Foundation
import os.log

/// Manages the ClipStack Login Item registration.
///
/// On macOS 13+ uses `SMAppService`; on earlier versions falls back to
/// an AppleScript invocation of System Events (without the deprecated
/// `SMLoginItemSetEnabled` which requires a helper bundle).
enum LoginItemManager {

    private static let logger = Logger(subsystem: "com.clipstack.ClipStack", category: "LoginItem")

    // MARK: - Public API

    static func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            setEnabledModern(enabled)
        } else {
            setEnabledLegacy(enabled)
        }
    }

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return isEnabledModern
        } else {
            return isEnabledLegacy
        }
    }

    // MARK: - macOS 13+ (SMAppService)

    @available(macOS 13.0, *)
    private static func setEnabledModern(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
                logger.info("Registered as login item (SMAppService).")
            } else {
                try service.unregister()
                logger.info("Unregistered as login item (SMAppService).")
            }
        } catch {
            logger.error("SMAppService error: \(error)")
        }
    }

    @available(macOS 13.0, *)
    private static var isEnabledModern: Bool {
        SMAppService.mainApp.status == .enabled
    }

    // MARK: - macOS 10.15–12 (AppleScript via System Events)

    private static func setEnabledLegacy(_ enabled: Bool) {
        guard let appPath = Bundle.main.bundlePath as String? else { return }
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "ClipStack"

        let script: String
        if enabled {
            script = """
            tell application "System Events"
                make new login item at end of login items with properties {path:"\(appPath)", hidden:false, name:"\(appName)"}
            end tell
            """
        } else {
            script = """
            tell application "System Events"
                delete login item "\(appName)"
            end tell
            """
        }

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
        if let error = error {
            logger.error("AppleScript login item error: \(error)")
        }
    }

    private static var isEnabledLegacy: Bool {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "ClipStack"
        let script = """
        tell application "System Events"
            return (name of every login item) contains "\(appName)"
        end tell
        """
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)
            return result.booleanValue
        }
        return false
    }
}

// Silence the deprecation warning for SMAppService import on older SDKs
import ServiceManagement
