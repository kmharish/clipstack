# ClipStack

A lightweight macOS menu bar clipboard manager that maintains an ordered stack of your copied items and lets you paste any of them with a single click or keyboard shortcut.

---

## Features

| Feature | Detail |
|---|---|
| Menu bar icon | Lives in the system menu bar — no Dock icon |
| Clipboard stack | Up to 50 configurable slots (default 10) |
| Smart paste | **CMD+V** pastes the *selected* stack item |
| Quick paste | **CMD+Shift+V** always pastes the *most recent* item |
| Keyboard navigation | Items 1–9 accessible via **CMD+1** … **CMD+9** |
| Persistence | History survives app restarts (Core Data) |
| Duplicate filtering | Ignores items already in the stack |
| Launch at Login | Optional auto-start via SMAppService / System Events |
| Accessibility | VoiceOver labels on all menu items |

---

## Requirements

- macOS 10.15 Catalina or later
- Xcode 15+ (to build from source)
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (to generate the `.xcodeproj`)

---

## Getting Started

### 1 — Generate the Xcode project

```bash
# Install xcodegen (once)
brew install xcodegen

# Generate ClipStack.xcodeproj
cd /path/to/clipstack
xcodegen generate
```

### 2 — Open in Xcode

```bash
open ClipStack.xcodeproj
```

### 3 — Grant Accessibility Permission

ClipStack intercepts **CMD+V** via `CGEventTap`, which requires Accessibility access:

1. Build & Run from Xcode (⌘R)
2. An alert will appear — click **Open System Settings**
3. Navigate to **Privacy & Security → Accessibility**
4. Toggle **ClipStack** on
5. Relaunch the app

---

## Project Structure

```
clipstack/
├── project.yml                         ← xcodegen configuration
├── ClipStack/
│   ├── App/
│   │   ├── main.swift                  ← Entry point
│   │   └── AppDelegate.swift           ← Composition root
│   ├── CoreData/
│   │   ├── ClipItem+CoreDataClass.swift
│   │   └── ClipItem+CoreDataProperties.swift
│   ├── Controllers/
│   │   ├── MenuBarController.swift     ← NSStatusItem + NSMenu
│   │   ├── PreferencesWindowController.swift
│   │   └── KeyboardShortcutManager.swift  ← CGEventTap
│   ├── Managers/
│   │   ├── ClipboardManager.swift      ← NSPasteboard polling
│   │   ├── PreferencesManager.swift    ← UserDefaults wrapper
│   │   ├── PersistenceController.swift ← Core Data stack
│   │   └── LoginItemManager.swift      ← Launch-at-login
│   ├── ViewModels/
│   │   └── ClipboardViewModel.swift    ← MVVM core (Combine)
│   ├── ClipStack.xcdatamodeld/         ← Core Data model
│   ├── Assets.xcassets/
│   ├── ClipStack.entitlements
│   └── Resources/
│       └── Info.plist
└── ClipStackTests/
    ├── ClipboardViewModelTests.swift
    ├── ClipboardManagerTests.swift
    └── PreferencesManagerTests.swift
```

---

## Architecture

ClipStack follows **MVVM** with Combine for reactive updates:

```
NSPasteboard ──poll──▶ ClipboardManager ──publisher──▶ ClipboardViewModel
                                                              │
                                          ┌───────────────────┤
                                          ▼                   ▼
                                  MenuBarController    KeyboardShortcutManager
                                  (NSStatusItem)       (CGEventTap)
                                          │
                                  PreferencesWindowController
```

- **Model** — `ClipItem` (NSManagedObject, Core Data)
- **ViewModel** — `ClipboardViewModel` (`@Published` properties, Combine pipelines)
- **View/Controllers** — `MenuBarController`, `PreferencesWindowController`
- **Services** — `ClipboardManager`, `PersistenceController`, `PreferencesManager`, `KeyboardShortcutManager`, `LoginItemManager`

---

## Preferences

Open via the menu bar icon → **Preferences…** (or **CMD+,**):

| Setting | Default | Description |
|---|---|---|
| Stack Size | 10 | Max items stored (1–50) |
| Launch at Login | Off | Auto-start on macOS login |
| Ignore duplicates | On | Skip items already in the stack |
| Trim whitespace | On | Strip leading/trailing whitespace |
| Show type icons | On | Display SF Symbol icons per content type |
| Clear History | — | Delete all items immediately |

---

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| **CMD+V** | Paste the currently *selected* stack item |
| **CMD+Shift+V** | Paste the *most recent* item (index 0) |
| **CMD+1 … CMD+9** | Select item 1–9 from the menu |
| **CMD+Shift+K** | Clear clipboard history |
| **CMD+,** | Open Preferences |
| **CMD+Q** | Quit ClipStack |

---

## Running Tests

```bash
xcodegen generate
xcodebuild test \
  -scheme ClipStack \
  -destination 'platform=macOS' \
  | xcpretty
```

---

## Privacy

ClipStack operates **entirely locally**. No clipboard content is ever sent to a server, logged to a file outside Core Data, or shared with any third party.

---

## License

MIT © 2024 ClipStack
