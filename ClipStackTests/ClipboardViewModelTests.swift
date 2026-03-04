import XCTest
import Combine
@testable import ClipStack

final class ClipboardViewModelTests: XCTestCase {

    // MARK: - Helpers

    private var cancellables = Set<AnyCancellable>()

    /// Creates a ViewModel backed by an in-memory Core Data store so tests
    /// are isolated from the real persistent store.
    private func makeViewModel(maxStack: Int = 5) -> ClipboardViewModel {
        let persistence = PersistenceController(inMemory: true)
        let preferences = PreferencesManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.maxStackSize = maxStack
        preferences.ignoreDuplicates = false    // easier to test deterministically
        preferences.trimWhitespace   = false

        let clipboardManager = ClipboardManager(preferences: preferences)

        return ClipboardViewModel(
            clipboardManager: clipboardManager,
            persistence:      persistence,
            preferences:      preferences
        )
    }

    // MARK: - Stack Tests

    func test_initialStack_isEmpty() {
        let vm = makeViewModel()
        XCTAssertTrue(vm.stack.isEmpty)
    }

    func test_selectedIndex_defaultsToZero() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.selectedIndex, 0)
    }

    func test_selectItem_updatesSelectedIndex() {
        let vm = makeViewModel()
        simulateEntry("Alpha", in: vm)
        simulateEntry("Beta",  in: vm)
        simulateEntry("Gamma", in: vm)

        vm.select(at: 2)
        XCTAssertEqual(vm.selectedIndex, 2)
    }

    func test_selectItem_outOfRange_doesNotChange() {
        let vm = makeViewModel()
        simulateEntry("Only", in: vm)
        vm.select(at: 0)

        vm.select(at: 99)
        XCTAssertEqual(vm.selectedIndex, 0)
    }

    func test_removeItem_shrinksStack() {
        let vm = makeViewModel()
        simulateEntry("A", in: vm)
        simulateEntry("B", in: vm)
        XCTAssertEqual(vm.stack.count, 2)

        vm.remove(at: 0)
        XCTAssertEqual(vm.stack.count, 1)
    }

    func test_clearAll_emptiesStack() {
        let vm = makeViewModel()
        simulateEntry("X", in: vm)
        simulateEntry("Y", in: vm)

        vm.clearAll()
        XCTAssertTrue(vm.stack.isEmpty)
    }

    // MARK: - Stack Limit Tests

    func test_stackLimit_evictsOldestItem() {
        let vm = makeViewModel(maxStack: 3)

        simulateEntry("First",  in: vm)
        simulateEntry("Second", in: vm)
        simulateEntry("Third",  in: vm)
        simulateEntry("Fourth", in: vm)   // should evict "First"

        XCTAssertEqual(vm.stack.count, 3)
        // Index 0 is most recent → "Fourth"
        XCTAssertEqual(vm.stack[0].content, "Fourth")
        // "First" (oldest) should be gone
        XCTAssertFalse(vm.stack.contains { $0.content == "First" })
    }

    // MARK: - Most Recent / Selected Item

    func test_mostRecentItem_isIndexZero() {
        let vm = makeViewModel()
        simulateEntry("Old",  in: vm)
        simulateEntry("New",  in: vm)
        XCTAssertEqual(vm.mostRecentItem?.content, "New")
    }

    func test_selectedItem_returnsCorrectItem() {
        let vm = makeViewModel()
        simulateEntry("Alpha", in: vm)
        simulateEntry("Beta",  in: vm)
        vm.select(at: 1)
        XCTAssertEqual(vm.selectedItem?.content, "Alpha")
    }

    func test_selectedItem_nilWhenEmpty() {
        let vm = makeViewModel()
        XCTAssertNil(vm.selectedItem)
    }

    // MARK: - Insertion Order

    func test_newItemInsertedAtFront() {
        let vm = makeViewModel()
        simulateEntry("First",  in: vm)
        simulateEntry("Second", in: vm)

        XCTAssertEqual(vm.stack[0].content, "Second")
        XCTAssertEqual(vm.stack[1].content, "First")
    }

    // MARK: - Helpers

    /// Directly feeds an entry into the ViewModel without going through the
    /// real pasteboard, by publishing directly on the ClipboardManager subject.
    private func simulateEntry(_ content: String, in vm: ClipboardViewModel) {
        let entry = ClipboardManager.ClipboardEntry(content: content, contentType: .text)
        vm.clipboardManager.newEntryPublisher.send(entry)
        // Drain the main run loop so @Published changes propagate
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
    }
}
