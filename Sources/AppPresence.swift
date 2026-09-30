import AppKit

/// Dictation runs as a menu-bar (accessory) app, and macOS never gives an accessory app a menu bar,
/// so with Settings open the top of the screen still showed Terminal's menus. While any Dictation
/// window is up it becomes a regular app with its own menus (Edit included, so ⌘V works in the key
/// fields); when the last window goes away it drops back to the Dock preference.
@MainActor
enum AppPresence {
    private static var visible = Set<ObjectIdentifier>()
    private static var observers: [ObjectIdentifier: NSObjectProtocol] = [:]

    static func present(_ w: NSWindow) {
        installMenu()
        let id = ObjectIdentifier(w)
        if observers[id] == nil {
            observers[id] = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: w, queue: .main
            ) { _ in MainActor.assumeIsolated { gone(id) } }
        }
        visible.insert(id)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        // Cooperative activation can refuse a menu-bar app; this still brings the window up.
        w.orderFrontRegardless()
    }

    /// For windows hidden with orderOut, which doesn't post willClose.
    static func hidden(_ w: NSWindow) { gone(ObjectIdentifier(w)) }

    private static func gone(_ id: ObjectIdentifier) {
        visible.remove(id)
        if visible.isEmpty { Prefs.applyDockPolicy() }
    }

    private static func installMenu() {
        guard NSApp.mainMenu == nil else { return }
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Dictation", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Dictation", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Dictation", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add(appMenu, to: main)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        add(edit, to: main)

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        add(window, to: main)
        NSApp.windowsMenu = window

        NSApp.mainMenu = main
    }

    private static func add(_ submenu: NSMenu, to main: NSMenu) {
        let item = NSMenuItem()
        item.submenu = submenu
        main.addItem(item)
    }
}
