import AppKit
import Combine
import os.log

/// Monitors `NSPasteboard` for changes and publishes new clipboard content.
///
/// Uses a repeating `Timer` (polling at `pollingInterval`) because
/// `NSPasteboard` does not expose a reliable change notification API.
final class ClipboardManager {

    // MARK: - Types

    /// A freshly detected clipboard entry.
    struct ClipboardEntry {
        let content: String
        let contentType: ClipItem.ContentType
    }

    // MARK: - Public Publisher

    /// Emits a `ClipboardEntry` each time the pasteboard changes.
    let newEntryPublisher = PassthroughSubject<ClipboardEntry, Never>()

    // MARK: - Private State

    private let pasteboard  = NSPasteboard.general
    private var changeCount: Int
    private var pollingTimer: Timer?
    private let pollingInterval: TimeInterval = 0.5
    private let preferences: PreferencesManager
    private let logger = Logger(subsystem: "com.clipstack.ClipStack", category: "ClipboardManager")

    // MARK: - Init

    init(preferences: PreferencesManager = .shared) {
        self.preferences  = preferences
        self.changeCount  = NSPasteboard.general.changeCount
    }

    // MARK: - Lifecycle

    func start() {
        guard pollingTimer == nil else { return }
        pollingTimer = Timer.scheduledTimer(
            withTimeInterval: pollingInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkForChanges()
        }
        logger.info("ClipboardManager started polling.")
    }

    func stop() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        logger.info("ClipboardManager stopped.")
    }

    // MARK: - Change Detection

    private func checkForChanges() {
        let newCount = pasteboard.changeCount
        guard newCount != changeCount else { return }
        changeCount = newCount

        guard let entry = readCurrentEntry() else { return }

        // Respect trimming preference
        let content = preferences.trimWhitespace
            ? entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
            : entry.content

        guard !content.isEmpty else { return }

        let finalEntry = ClipboardEntry(content: content, contentType: entry.contentType)
        newEntryPublisher.send(finalEntry)
        logger.debug("New clipboard entry: type=\(entry.contentType.rawValue) length=\(content.count)")
    }

    // MARK: - Pasteboard Reading

    /// Attempts to read a meaningful string representation of the current pasteboard contents.
    private func readCurrentEntry() -> ClipboardEntry? {
        // Priority order: URL string → file paths → RTF → plain text
        if let urlString = pasteboard.string(forType: .URL) ?? pasteboard.string(forType: .string),
           let url = URL(string: urlString),
           url.scheme != nil {
            return ClipboardEntry(content: urlString, contentType: .url)
        }

        if let filenames = pasteboard.propertyList(
               forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")
           ) as? [String], !filenames.isEmpty {
            let joined = filenames.joined(separator: "\n")
            return ClipboardEntry(content: joined, contentType: .file)
        }

        // RTF: extract plain text representation
        if let rtfData = pasteboard.data(forType: .rtf),
           let attributed = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            return ClipboardEntry(content: attributed.string, contentType: .rtf)
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            // Heuristic URL check
            if let url = URL(string: text), url.scheme != nil, url.host != nil {
                return ClipboardEntry(content: text, contentType: .url)
            }
            return ClipboardEntry(content: text, contentType: .text)
        }

        return nil
    }

    // MARK: - Write

    /// Places the given string onto `NSPasteboard.general`.
    func writeToClipboard(_ content: String) {
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)
        // Update our local change count so we don't re-capture what we just wrote.
        changeCount = pasteboard.changeCount
        logger.debug("Wrote to clipboard: \(content.prefix(40))")
    }
}
