import AppKit

// Entry point – must live in main.swift (not use @main) when AppDelegate
// is a plain NSObject subclass without a static `main()` method.

let app      = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
