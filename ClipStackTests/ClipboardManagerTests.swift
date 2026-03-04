import XCTest
import Combine
@testable import ClipStack

final class ClipboardManagerTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    // MARK: - writeToClipboard

    func test_writeToClipboard_setsString() {
        let prefs   = PreferencesManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let manager = ClipboardManager(preferences: prefs)

        let expected = "Hello, ClipStack!"
        manager.writeToClipboard(expected)

        let actual = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(actual, expected)
    }

    func test_writeToClipboard_doesNotTriggerNewEntry() {
        let prefs   = PreferencesManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let manager = ClipboardManager(preferences: prefs)

        var receivedEntries: [ClipboardManager.ClipboardEntry] = []

        manager.newEntryPublisher
            .sink { receivedEntries.append($0) }
            .store(in: &cancellables)

        manager.start()
        manager.writeToClipboard("ShouldNotEcho")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0))   // wait > polling interval
        manager.stop()

        XCTAssertTrue(receivedEntries.isEmpty,
            "Writing to clipboard internally must not re-emit a new entry.")
    }

    // MARK: - start / stop

    func test_stopAfterStart_doesNotCrash() {
        let prefs   = PreferencesManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let manager = ClipboardManager(preferences: prefs)
        manager.start()
        manager.stop()
        // No assertion needed – we're checking for no crash.
    }

    func test_startTwice_doesNotCreateDuplicateTimer() {
        let prefs   = PreferencesManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let manager = ClipboardManager(preferences: prefs)
        manager.start()
        manager.start()   // second call should be a no-op

        var count = 0
        manager.newEntryPublisher
            .sink { _ in count += 1 }
            .store(in: &cancellables)

        manager.stop()
        // No duplicate timers → no crash, count unchanged
        XCTAssertEqual(count, 0)
    }
}
