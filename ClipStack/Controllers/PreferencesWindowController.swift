import AppKit
import Combine
import os.log

/// NSWindowController that presents the ClipStack Preferences panel.
///
/// The window is built programmatically (no XIB/storyboard) to keep
/// the project self-contained.  All controls bind directly to
/// `PreferencesManager.shared`.
final class PreferencesWindowController: NSWindowController {

    // MARK: - Dependencies

    private let viewModel: ClipboardViewModel
    private let preferences = PreferencesManager.shared
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.clipstack.ClipStack", category: "Preferences")

    // MARK: - Controls

    private lazy var maxSizeLabel    = makeLabel("Stack Size:")
    private lazy var maxSizeStepper  = makeStepper(min: 1, max: 50, value: Double(preferences.maxStackSize))
    private lazy var maxSizeField    = makeTextField(String(preferences.maxStackSize))

    private lazy var launchAtLoginCheckbox = makeCheckbox(
        "Launch at Login",
        checked: preferences.launchAtLogin
    )
    private lazy var showIconsCheckbox = makeCheckbox(
        "Show type icons in menu",
        checked: preferences.showTypeIcons
    )
    private lazy var trimWhitespaceCheckbox = makeCheckbox(
        "Trim whitespace from copied text",
        checked: preferences.trimWhitespace
    )
    private lazy var ignoreDuplicatesCheckbox = makeCheckbox(
        "Ignore duplicates",
        checked: preferences.ignoreDuplicates
    )
    private lazy var clearHistoryButton = makeButton("Clear Clipboard History", action: #selector(clearHistory))

    // MARK: - Init

    init(viewModel: ClipboardViewModel) {
        self.viewModel = viewModel
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            styleMask:   [.titled, .closable, .miniaturizable],
            backing:     .buffered,
            defer:       false
        )
        window.title = "ClipStack Preferences"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - UI Construction

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        // --- Stack Size Row ---
        let stackSizeRow = makeHStack([
            maxSizeLabel,
            maxSizeStepper,
            maxSizeField
        ])

        // --- Behaviour Group ---
        let behaviourBox = makeGroupBox(title: "Behaviour", subviews: [
            stackSizeRow,
            launchAtLoginCheckbox,
            ignoreDuplicatesCheckbox,
            trimWhitespaceCheckbox,
            showIconsCheckbox
        ])

        // --- History Group ---
        let historyBox = makeGroupBox(title: "History", subviews: [clearHistoryButton])

        // --- Shortcut hint (read-only) ---
        let shortcutHint = makeLabel(
            "CMD+V → paste selected  |  CMD+Shift+V → paste most recent"
        )
        shortcutHint.font = .systemFont(ofSize: 11)
        shortcutHint.textColor = .secondaryLabelColor

        // --- Root stack ---
        let root = NSStackView(views: [behaviourBox, historyBox, shortcutHint])
        root.orientation = .vertical
        root.alignment   = .leading
        root.spacing     = 16
        root.edgeInsets  = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])

        wireControls()
    }

    // MARK: - Control Wiring

    private func wireControls() {
        maxSizeStepper.target  = self
        maxSizeStepper.action  = #selector(maxSizeStepperChanged(_:))

        maxSizeField.delegate  = self

        launchAtLoginCheckbox.target   = self
        launchAtLoginCheckbox.action   = #selector(launchAtLoginChanged(_:))

        showIconsCheckbox.target       = self
        showIconsCheckbox.action       = #selector(showIconsChanged(_:))

        trimWhitespaceCheckbox.target  = self
        trimWhitespaceCheckbox.action  = #selector(trimWhitespaceChanged(_:))

        ignoreDuplicatesCheckbox.target = self
        ignoreDuplicatesCheckbox.action = #selector(ignoreDuplicatesChanged(_:))
    }

    // MARK: - Actions

    @objc private func maxSizeStepperChanged(_ sender: NSStepper) {
        let value = Int(sender.intValue)
        preferences.maxStackSize = value
        maxSizeField.stringValue = String(value)
    }

    @objc private func launchAtLoginChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        preferences.launchAtLogin = enabled
        LoginItemManager.setEnabled(enabled)
    }

    @objc private func showIconsChanged(_ sender: NSButton) {
        preferences.showTypeIcons = sender.state == .on
    }

    @objc private func trimWhitespaceChanged(_ sender: NSButton) {
        preferences.trimWhitespace = sender.state == .on
    }

    @objc private func ignoreDuplicatesChanged(_ sender: NSButton) {
        preferences.ignoreDuplicates = sender.state == .on
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear Clipboard History?"
        alert.informativeText = "All \(viewModel.stack.count) saved items will be permanently deleted."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        viewModel.clearAll()
        logger.info("History cleared from Preferences.")
    }

    // MARK: - Factory Helpers

    private func makeLabel(_ text: String) -> NSTextField {
        let tf = NSTextField(labelWithString: text)
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }

    private func makeTextField(_ text: String) -> NSTextField {
        let tf = NSTextField(string: text)
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.widthAnchor.constraint(equalToConstant: 48).isActive = true
        tf.alignment = .center
        return tf
    }

    private func makeStepper(min: Double, max: Double, value: Double) -> NSStepper {
        let s = NSStepper()
        s.minValue = min
        s.maxValue = max
        s.doubleValue = value
        s.increment = 1
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }

    private func makeCheckbox(_ title: String, checked: Bool) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        b.state = checked ? .on : .off
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    private func makeButton(_ title: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    private func makeHStack(_ views: [NSView]) -> NSStackView {
        let sv = NSStackView(views: views)
        sv.orientation = .horizontal
        sv.alignment   = .centerY
        sv.spacing     = 8
        return sv
    }

    private func makeGroupBox(title: String, subviews: [NSView]) -> NSBox {
        let box = NSBox()
        box.title = title
        box.translatesAutoresizingMaskIntoConstraints = false

        let inner = NSStackView(views: subviews)
        inner.orientation = .vertical
        inner.alignment   = .leading
        inner.spacing     = 8
        inner.translatesAutoresizingMaskIntoConstraints = false
        box.contentView?.addSubview(inner)

        if let cv = box.contentView {
            NSLayoutConstraint.activate([
                inner.topAnchor.constraint(equalTo: cv.topAnchor, constant: 8),
                inner.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -8),
                inner.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 8),
                inner.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -8)
            ])
        }
        return box
    }
}

// MARK: - NSTextFieldDelegate (stack size text field)
extension PreferencesWindowController: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField,
              field === maxSizeField,
              let value = Int(field.stringValue), value > 0 else { return }
        preferences.maxStackSize = value
        maxSizeStepper.intValue  = Int32(value)
    }
}
