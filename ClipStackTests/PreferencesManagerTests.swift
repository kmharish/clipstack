import XCTest
@testable import ClipStack

final class PreferencesManagerTests: XCTestCase {

    /// Each test gets a fresh, isolated UserDefaults suite.
    private func makePreferences() -> PreferencesManager {
        let suite = UUID().uuidString
        return PreferencesManager(defaults: UserDefaults(suiteName: suite)!)
    }

    // MARK: - Defaults

    func test_defaultMaxStackSize_is10() {
        let prefs = makePreferences()
        XCTAssertEqual(prefs.maxStackSize, 10)
    }

    func test_defaultLaunchAtLogin_isFalse() {
        let prefs = makePreferences()
        XCTAssertFalse(prefs.launchAtLogin)
    }

    func test_defaultShowTypeIcons_isTrue() {
        let prefs = makePreferences()
        XCTAssertTrue(prefs.showTypeIcons)
    }

    func test_defaultTrimWhitespace_isTrue() {
        let prefs = makePreferences()
        XCTAssertTrue(prefs.trimWhitespace)
    }

    func test_defaultIgnoreDuplicates_isTrue() {
        let prefs = makePreferences()
        XCTAssertTrue(prefs.ignoreDuplicates)
    }

    // MARK: - Persistence

    func test_maxStackSize_persists() {
        let suite = UUID().uuidString
        let prefs1 = PreferencesManager(defaults: UserDefaults(suiteName: suite)!)
        prefs1.maxStackSize = 25

        let prefs2 = PreferencesManager(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(prefs2.maxStackSize, 25)
    }

    func test_launchAtLogin_persists() {
        let suite = UUID().uuidString
        let prefs1 = PreferencesManager(defaults: UserDefaults(suiteName: suite)!)
        prefs1.launchAtLogin = true

        let prefs2 = PreferencesManager(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertTrue(prefs2.launchAtLogin)
    }

    // MARK: - Keyboard Shortcut Storage

    func test_pasteSelectedKeyCode_defaultsToV() {
        let prefs = makePreferences()
        // keyCode 9 = 'v'
        XCTAssertEqual(prefs.pasteSelectedKeyCode, 9)
    }

    func test_pasteSelectedKeyCode_roundTrip() {
        let prefs = makePreferences()
        prefs.pasteSelectedKeyCode = 0x08   // 'c'
        XCTAssertEqual(prefs.pasteSelectedKeyCode, 0x08)
    }

    func test_pasteSelectedModifiers_includesCommand() {
        let prefs = makePreferences()
        XCTAssertTrue(prefs.pasteSelectedModifiers.contains(.command))
    }
}
