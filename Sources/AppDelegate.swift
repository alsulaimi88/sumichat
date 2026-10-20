import AppKit
import WebKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    /// "SumiChat", or "SumiChat Dev" for test builds (see build.sh dev).
    static let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "SumiChat"

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    private var accounts: [Account] = []
    private var windows: [UUID: AccountWindow] = [:]
    private var lastActiveAccount: UUID?
    private let notifier = Notifier()
    private let updater = Updater()
    private let translator = Translator()

    /// All accounts as tabs in one window (the default), or one window each.
    private enum Layout: String { case tabs, separate }
    private var layout: Layout {
        get { Layout(rawValue: UserDefaults.standard.string(forKey: "WindowLayout") ?? "") ?? .tabs }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "WindowLayout") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        notifier.setUp()
        notifier.translator = translator
        translator.onLanguageReady = { [weak self] language in
            guard let self else { return }
            notifier.showLanguageReady(language)
            for accountWindow in windows.values {
                accountWindow.browser.webView.evaluateJavaScript(
                    "window.__sumiResetTranslations && window.__sumiResetTranslations()")
            }
        }
        translator.onMissingLanguagesChanged = { [weak self] in self?.updateLayoutControls() }
        notifier.onDownloadLanguage = { [weak self] code in
            guard let self else { return }
            Task { await self.translator.download(Locale.Language(identifier: code), over: self.currentWindow?.window) }
        }
        notifier.onMessageClick = { [weak self] accountID, id in
            guard let self, let accountWindow = windows[accountID] else { return }
            show(accountWindow)
            accountWindow.browser.notificationClicked(id: id)
        }
        notifier.onReply = { [weak self] accountID, id, chat, text in
            guard let accountWindow = self?.windows[accountID] else { return "no-account" }
            return await accountWindow.browser.reply(toNotification: id, chatTitle: chat, text: text)
        }

        updater.onUpdateReady = { [weak self] _ in self?.updateLayoutControls() }

        NotificationCenter.default.addObserver(
            self, selector: #selector(windowBecameKey(_:)), name: NSWindow.didBecomeKeyNotification, object: nil
        )

        accounts = AccountList.load()
        for (index, account) in accounts.enumerated() {
            open(account, cascadeIndex: index)
        }
        accountsChanged()
        applyLayout()
        if let primary = accounts.first.flatMap({ windows[$0.id] }) { show(primary) }

        updater.checkInBackgroundIfRequested()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if layout == .tabs { applyLayout() }
            if let current = currentWindow { show(current) }
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // keep running so notifications keep arriving
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard accounts.count > 1 else { return nil }
        let menu = NSMenu()
        for (index, account) in accounts.enumerated() {
            let unread = windows[account.id]?.unread ?? 0
            let item = NSMenuItem(title: unread > 0 ? "\(account.name) (\(unread))" : account.name,
                                  action: #selector(showAccount(_:)), keyEquivalent: "")
            item.tag = index
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    // MARK: Accounts

    private func open(_ account: Account, cascadeIndex: Int) {
        let accountWindow = AccountWindow(account: account, notifier: notifier, translator: translator,
                                          cascadeIndex: cascadeIndex)
        accountWindow.onUnreadChange = { [weak self] in self?.updateDockBadge() }
        windows[account.id] = accountWindow
    }

    /// Puts the account windows together as tabs, or apart as separate windows.
    private func applyLayout() {
        let ordered = accounts.compactMap { windows[$0.id] }
        guard let first = ordered.first else { return }

        switch layout {
        case .tabs:
            for accountWindow in ordered { accountWindow.window.tabbingMode = .preferred }
            first.window.orderFront(nil)
            for accountWindow in ordered.dropFirst()
            where !(first.window.tabbedWindows ?? []).contains(accountWindow.window) {
                first.window.addTabbedWindow(accountWindow.window, ordered: .above)
            }
        case .separate:
            for (index, accountWindow) in ordered.enumerated() {
                let window = accountWindow.window
                if index > 0, (window.tabbedWindows?.count ?? 1) > 1 {
                    window.moveTabToNewWindow(nil)
                    let origin = first.window.frame.origin
                    window.setFrameOrigin(NSPoint(x: origin.x + CGFloat(index) * 32, y: origin.y - CGFloat(index) * 32))
                }
                window.tabbingMode = .disallowed
                window.orderFront(nil)
            }
        }
        updateLayoutControls()
    }

    /// Refreshes the title bar buttons and the menu bar.
    private func updateLayoutControls() {
        let merged = layout == .tabs
        for accountWindow in windows.values {
            accountWindow.configureLayoutButton(merged: merged, visible: accounts.count > 1,
                                                target: self, action: #selector(toggleLayout(_:)))
            accountWindow.configureUpdateButton(readyVersion: updater.readyVersion,
                                                target: self, action: #selector(restartToUpdate(_:)))
            accountWindow.configureTranslateButton(menu: Translator.isAvailable ? {
                let menu = NSMenu()
                MainMenu.translateItems(target: self, shortcuts: false,
                                        missing: Array(translator.missingLanguages.values)).forEach(menu.addItem)
                return menu
            }() : nil)
        }
        NSApp.mainMenu = MainMenu.build(target: self, accounts: accounts, merged: merged,
                                        updateReady: updater.readyVersion,
                                        missingLanguages: Array(translator.missingLanguages.values))
    }

    /// Saves the list and refreshes everything that shows account names.
    private func accountsChanged() {
        AccountList.save(accounts)
        let multiple = accounts.count > 1
        for account in accounts {
            windows[account.id]?.account = account
            windows[account.id]?.showsAccountName = multiple
        }
        notifier.accountNames = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
        notifier.showsAccountNames = multiple
        updateLayoutControls()
        updateDockBadge()
    }

    private func updateDockBadge() {
        let total = windows.values.reduce(0) { $0 + $1.unread }
        NSApp.dockTile.badgeLabel = total > 0 ? String(total) : nil
    }

    /// The account in front: menu commands like Reload act on it.
    private var currentWindow: AccountWindow? {
        if let key = NSApp.keyWindow, let match = windows.values.first(where: { $0.window === key }) { return match }
        if let id = lastActiveAccount, let match = windows[id] { return match }
        return accounts.first.flatMap { windows[$0.id] }
    }

    @objc private func windowBecameKey(_ note: Notification) {
        guard let window = note.object as? NSWindow else { return }
        lastActiveAccount = windows.first(where: { $0.value.window === window })?.key ?? lastActiveAccount
    }

    private func show(_ accountWindow: AccountWindow) {
        // In tab mode, an account whose tab was closed comes back as a tab of the open window.
        if layout == .tabs, !accountWindow.window.isVisible,
           let anchor = windows.values.first(where: { $0 !== accountWindow && $0.window.isVisible }) {
            accountWindow.window.tabbingMode = .preferred
            anchor.window.addTabbedWindow(accountWindow.window, ordered: .above)
        }
        accountWindow.window.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func askForName(title: String, message: String, initial: String, confirm: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    // MARK: Menu actions

    @objc func newAccount(_ sender: Any?) {
        guard AccountList.supportsMultiple else {
            let alert = NSAlert()
            alert.messageText = "More accounts need macOS 14"
            alert.informativeText = "Each account keeps its own login, which needs macOS Sonoma (14) or later."
            alert.runModal()
            return
        }
        guard let name = askForName(
            title: "Add an account",
            message: "Give it a name, like Business or Personal. Then scan the QR code with the phone for that account.",
            initial: "Account \(accounts.count + 1)", confirm: "Add"
        ) else { return }

        let account = Account(id: UUID(), name: name, isPrimary: false)
        accounts.append(account)
        open(account, cascadeIndex: accounts.count - 1)
        accountsChanged()
        applyLayout()
        if let accountWindow = windows[account.id] { show(accountWindow) }
    }

    @objc func renameAccount(_ sender: Any?) {
        guard let current = currentWindow, let index = accounts.firstIndex(where: { $0.id == current.account.id }),
              let name = askForName(title: "Rename account", message: "This name shows in the window title and notifications.",
                                    initial: accounts[index].name, confirm: "Rename") else { return }
        accounts[index].name = name
        accountsChanged()
    }

    @objc func removeAccount(_ sender: Any?) {
        guard let current = currentWindow, let index = accounts.firstIndex(where: { $0.id == current.account.id }) else { return }
        let account = accounts[index]

        let alert = NSAlert()
        guard !account.isPrimary else {
            alert.messageText = "The first account can't be removed"
            alert.informativeText = "To sign it out, use WhatsApp's own menu (⋮ → Log out) in its window."
            alert.runModal()
            return
        }
        alert.messageText = "Remove “\(account.name)”?"
        alert.informativeText = "This signs the account out of SumiChat and deletes its saved data on this Mac. Your chats stay on your phone."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        windows.removeValue(forKey: account.id)?.tearDown()
        accounts.remove(at: index)
        accountsChanged()
        if let primary = accounts.first.flatMap({ windows[$0.id] }) { show(primary) }

        if #available(macOS 14.0, *) {
            // Give WebKit a moment to let go of the store before deleting it.
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                do {
                    try await WKWebsiteDataStore.remove(forIdentifier: account.id)
                } catch {
                    NSLog("SumiChat: couldn't delete data for \(account.name): \(error.localizedDescription)")
                }
            }
        }
    }

    /// The "+" button in the tab bar.
    @objc func newWindowForTab(_ sender: Any?) {
        newAccount(sender)
    }

    @objc func toggleLayout(_ sender: Any?) {
        layout = layout == .tabs ? .separate : .tabs
        applyLayout()
        if let current = currentWindow { show(current) }
    }

    @objc func showAccount(_ sender: NSMenuItem) {
        guard accounts.indices.contains(sender.tag), let accountWindow = windows[accounts[sender.tag].id] else { return }
        show(accountWindow)
    }

    @objc func reloadPage(_ sender: Any?) {
        currentWindow?.browser.reload()
    }

    @objc func zoomIn(_ sender: Any?) {
        guard let webView = currentWindow?.browser.webView else { return }
        webView.pageZoom = min(webView.pageZoom + 0.1, 3)
    }

    @objc func zoomOut(_ sender: Any?) {
        guard let webView = currentWindow?.browser.webView else { return }
        webView.pageZoom = max(webView.pageZoom - 0.1, 0.5)
    }

    @objc func actualSize(_ sender: Any?) {
        currentWindow?.browser.webView.pageZoom = 1
    }

    // MARK: Translation

    @objc func toggleChatTranslation(_ sender: Any?) {
        guard let browser = currentWindow?.browser else { return }
        browser.setChatTranslation(!browser.isTranslatingChat)
    }

    @objc func translateMyMessage(_ sender: Any?) {
        guard let browser = currentWindow?.browser else { return }
        Task { await browser.translateMyMessage() }
    }

    @objc func downloadLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        Task { await translator.download(Locale.Language(identifier: code), over: currentWindow?.window) }
    }

    @objc func toggleNotificationTranslation(_ sender: Any?) {
        Translator.translatesNotifications.toggle()
    }

    @objc func setTranslateTarget(_ sender: NSMenuItem) {
        let code = sender.representedObject as? String ?? ""
        Translator.targetCode = code.isEmpty ? nil : code
        for accountWindow in windows.values {
            accountWindow.browser.webView.evaluateJavaScript("window.__sumiResetTranslations && window.__sumiResetTranslations()")
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleChatTranslation(_:)):
            menuItem.state = currentWindow?.browser.isTranslatingChat == true ? .on : .off
        case #selector(toggleNotificationTranslation(_:)):
            menuItem.state = Translator.translatesNotifications ? .on : .off
        case #selector(setTranslateTarget(_:)):
            let code = menuItem.representedObject as? String ?? ""
            menuItem.state = code == (Translator.targetCode ?? "") ? .on : .off
        default:
            break
        }
        return true
    }

    @objc func checkForUpdates(_ sender: Any?) {
        updater.checkForUpdates()
    }

    @objc func restartToUpdate(_ sender: Any?) {
        updater.installAndRelaunch()
    }

    @objc func openDownloadsFolder(_ sender: Any?) {
        NSWorkspace.shared.open(Downloads.folder)
    }
}
