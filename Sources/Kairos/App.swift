import AppKit

@main
@MainActor
enum KairosMain {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = Settings.shared
    lazy var store = ClipboardStore(settings: settings)
    lazy var panel = PanelController(store: store, settings: settings)

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.start()
        HotKey.shared.onPress = { [weak self] in self?.panel.toggle() }
        HotKey.shared.register(settings.shortcut)

        // Until setup is done, open straight into the setup screen.
        if !settings.hasCompletedSetup {
            panel.show()
        }
    }

    // Opening Kairos again (Spotlight, Finder) while it's running shows the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.show()
        return false
    }
}
