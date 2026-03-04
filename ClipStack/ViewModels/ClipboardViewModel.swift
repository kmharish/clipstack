import Foundation
import Combine
import os.log

/// Central MVVM ViewModel that owns the in-memory clipboard stack
/// and coordinates between `ClipboardManager`, `PersistenceController`,
/// and all UI controllers.
///
/// All mutations happen on the main thread; Combine subscriptions are
/// received on `DispatchQueue.main`.
final class ClipboardViewModel: ObservableObject {

    // MARK: - Published State

    /// Ordered clipboard history; index 0 is the most recently copied item.
    @Published private(set) var stack: [ClipItem] = []

    /// Index of the item that will be pasted when the user triggers "paste selected".
    /// Defaults to 0 (the most recent item).
    @Published private(set) var selectedIndex: Int = 0

    // MARK: - Dependencies

    let clipboardManager: ClipboardManager
    private let persistence: PersistenceController
    private let preferences: PreferencesManager
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.clipstack.ClipStack", category: "ViewModel")

    // MARK: - Init

    init(
        clipboardManager: ClipboardManager = ClipboardManager(),
        persistence: PersistenceController = .shared,
        preferences: PreferencesManager = .shared
    ) {
        self.clipboardManager = clipboardManager
        self.persistence      = persistence
        self.preferences      = preferences

        loadFromPersistence()
        subscribeToClipboardChanges()
        subscribeToPreferenceChanges()
        clipboardManager.start()
    }

    deinit {
        clipboardManager.stop()
    }

    // MARK: - Stack Access

    /// The currently selected `ClipItem`, or `nil` if the stack is empty.
    var selectedItem: ClipItem? {
        guard !stack.isEmpty, stack.indices.contains(selectedIndex) else { return nil }
        return stack[selectedIndex]
    }

    /// The most recently copied item (always index 0).
    var mostRecentItem: ClipItem? { stack.first }

    // MARK: - Stack Mutations

    /// Selects the item at `index` as the active paste target.
    func select(at index: Int) {
        guard stack.indices.contains(index) else { return }
        selectedIndex = index
        logger.debug("Selected item at index \(index)")
    }

    /// Removes the item at `index` from the stack.
    func remove(at index: Int) {
        guard stack.indices.contains(index) else { return }
        let item = stack[index]
        persistence.viewContext.delete(item)
        stack.remove(at: index)
        // Keep selectedIndex in valid range
        if selectedIndex >= stack.count {
            selectedIndex = max(0, stack.count - 1)
        }
        reorderSortKeys()
        persistence.save()
        logger.debug("Removed item at index \(index)")
    }

    /// Removes all items from the stack.
    func clearAll() {
        persistence.deleteAllItems()
        stack.removeAll()
        selectedIndex = 0
        logger.info("Cleared clipboard stack.")
    }

    // MARK: - Paste Helpers

    /// Writes the selected item's content to the system clipboard
    /// and returns the content string so the caller can simulate a paste.
    /// Returns `nil` if the stack is empty.
    @discardableResult
    func prepareSelectedForPaste() -> String? {
        guard let item = selectedItem, let content = item.content else { return nil }
        clipboardManager.writeToClipboard(content)
        return content
    }

    /// Writes the most recent item to the clipboard (index 0).
    @discardableResult
    func prepareMostRecentForPaste() -> String? {
        guard let item = mostRecentItem, let content = item.content else { return nil }
        clipboardManager.writeToClipboard(content)
        return content
    }

    // MARK: - Private: Subscriptions

    private func subscribeToClipboardChanges() {
        clipboardManager.newEntryPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entry in
                self?.addEntry(entry)
            }
            .store(in: &cancellables)
    }

    private func subscribeToPreferenceChanges() {
        preferences.$maxStackSize
            .dropFirst()            // skip initial emission
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newMax in
                self?.enforceStackLimit(max: newMax)
            }
            .store(in: &cancellables)
    }

    // MARK: - Private: Adding Items

    private func addEntry(_ entry: ClipboardManager.ClipboardEntry) {
        // Duplicate check
        if preferences.ignoreDuplicates,
           stack.contains(where: { $0.content == entry.content }) {
            logger.debug("Ignoring duplicate: \(entry.content.prefix(20))")
            return
        }

        // Evict oldest if at capacity
        let max = preferences.maxStackSize
        while stack.count >= max {
            let lastIndex = stack.count - 1
            persistence.viewContext.delete(stack[lastIndex])
            stack.removeLast()
        }

        // Insert at front (index 0 = most recent)
        let newSortOrder = Int32(0)
        let item = persistence.insertItem(
            content:     entry.content,
            contentType: entry.contentType.rawValue,
            sortOrder:   newSortOrder
        )

        stack.insert(item, at: 0)
        reorderSortKeys()
        persistence.save()

        // Reset selection to the new item
        selectedIndex = 0
        logger.debug("Added item: \(entry.content.prefix(40))")
    }

    // MARK: - Private: Helpers

    private func loadFromPersistence() {
        stack = persistence.fetchAllItems()
        logger.info("Loaded \(self.stack.count) items from persistence.")
    }

    /// Updates `sortOrder` to match the current array indices.
    private func reorderSortKeys() {
        for (index, item) in stack.enumerated() {
            item.sortOrder = Int32(index)
        }
    }

    /// Trims the stack to at most `max` items, removing from the end.
    private func enforceStackLimit(max limit: Int) {
        while stack.count > limit {
            let lastIndex = stack.count - 1
            persistence.viewContext.delete(stack[lastIndex])
            stack.removeLast()
        }
        if selectedIndex >= stack.count {
            selectedIndex = max(0, stack.count - 1)
        }
        persistence.save()
    }
}
