import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let appName = "SumiChat"

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    private var window: NSWindow!
    private var browser: BrowserController!
    private let notifier = Notifier()
    private let updater = Updater()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build(target: self)
        notifier.setUp()

        browser = BrowserController(notifier: notifier)
        browser.onUnreadCountChange = { [weak self] count in self?.updateUnread(count) }
        notifier.onMessageClick = { [weak self] id in
            self?.showMainWindow(nil)
            self?.browser.notificationClicked(id: id)
        }

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = Self.appName
        window.minSize = NSSize(width: 720, height: 500)
        window.isReleasedWhenClosed = false // closing just hides it; the Dock icon brings it back
        window.contentView = browser.webView
        window.center()
        window.setFrameAutosaveName("MainWindow")
        window.makeKeyAndOrderFront(nil)
        activate()

        browser.load()
        updater.checkIfDue()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow(nil)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // keep running so notifications keep arriving
    }

    private func updateUnread(_ count: Int) {
        NSApp.dockTile.badgeLabel = count > 0 ? String(count) : nil
        window.title = count > 0 ? "\(Self.appName) (\(count))" : Self.appName
    }

    private func activate() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: Menu actions

    @objc func showMainWindow(_ sender: Any?) {
        window.makeKeyAndOrderFront(nil)
        activate()
    }

    @objc func reloadPage(_ sender: Any?) {
        browser.reload()
    }

    @objc func zoomIn(_ sender: Any?) {
        browser.webView.pageZoom = min(browser.webView.pageZoom + 0.1, 3)
    }

    @objc func zoomOut(_ sender: Any?) {
        browser.webView.pageZoom = max(browser.webView.pageZoom - 0.1, 0.5)
    }

    @objc func actualSize(_ sender: Any?) {
        browser.webView.pageZoom = 1
    }

    @objc func checkForUpdates(_ sender: Any?) {
        updater.check(userInitiated: true)
    }

    @objc func openDownloadsFolder(_ sender: Any?) {
        NSWorkspace.shared.open(Downloads.folder)
    }
}
