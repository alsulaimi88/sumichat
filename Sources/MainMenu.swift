import AppKit

/// The menu bar. The Edit menu matters: without it Cmd+C / Cmd+V don't work in the web view.
@MainActor
enum MainMenu {
    static func build(target: AppDelegate, accounts: [Account], merged: Bool, updateReady: String?,
                      missingLanguages: [Locale.Language]) -> NSMenu {
        let name = AppDelegate.appName
        let main = NSMenu()

        let app = submenu(in: main, title: name)
        app.addItem(withTitle: "About \(name)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        if let version = updateReady {
            app.addItem(item("Restart to Update to \(version)", #selector(AppDelegate.restartToUpdate(_:)), "", [], target))
        } else {
            app.addItem(item("Check for Updates…", #selector(AppDelegate.checkForUpdates(_:)), "", [], target))
        }
        app.addItem(.separator())
        app.addItem(withTitle: "Hide \(name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
            .keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let file = submenu(in: main, title: "File")
        file.addItem(item("New Account…", #selector(AppDelegate.newAccount(_:)), "n", [.command], target))
        file.addItem(item("Rename Account…", #selector(AppDelegate.renameAccount(_:)), "", [], target))
        if accounts.count > 1 {
            file.addItem(item("Remove Account…", #selector(AppDelegate.removeAccount(_:)), "", [], target))
        }
        file.addItem(.separator())
        file.addItem(item("Open Downloads Folder", #selector(AppDelegate.openDownloadsFolder(_:)), "l", [.command, .option], target))
        file.addItem(.separator())
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let edit = submenu(in: main, title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let view = submenu(in: main, title: "View")
        view.addItem(item("Reload", #selector(AppDelegate.reloadPage(_:)), "r", [.command], target))
        view.addItem(.separator())
        let themes = NSMenu(title: "Theme")
        for theme in Theme.all {
            if theme.isOriginal { themes.addItem(.separator()) }
            let entry = item(theme.name, #selector(AppDelegate.setTheme(_:)), "", [], target)
            entry.representedObject = theme.id
            themes.addItem(entry)
        }
        let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        themeItem.submenu = themes
        view.addItem(themeItem)
        view.addItem(item("Mac Layout", #selector(AppDelegate.toggleMacLayout(_:)), "s", [.command, .control], target))
        view.addItem(.separator())
        view.addItem(item("Actual Size", #selector(AppDelegate.actualSize(_:)), "0", [.command], target))
        view.addItem(item("Zoom In", #selector(AppDelegate.zoomIn(_:)), "=", [.command], target))
        view.addItem(item("Zoom Out", #selector(AppDelegate.zoomOut(_:)), "-", [.command], target))
        view.addItem(.separator())
        view.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.command, .control]

        if Translator.isAvailable {
            let translate = submenu(in: main, title: "Translate")
            translateItems(target: target, shortcuts: true, missing: missingLanguages).forEach(translate.addItem)
        }

        let window = submenu(in: main, title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        if accounts.count > 1 {
            window.addItem(.separator())
            window.addItem(item(merged ? "Separate Account Windows" : "Merge Accounts into One Window",
                                #selector(AppDelegate.toggleLayout(_:)), "", [], target))
        }
        window.addItem(.separator())
        // One entry per account: ⌘1, ⌘2, … bring that account's window to the front.
        for (index, account) in accounts.enumerated() {
            let title = accounts.count > 1 ? account.name : name
            let entry = item(title, #selector(AppDelegate.showAccount(_:)), index < 9 ? String(index + 1) : "", [.command], target)
            entry.tag = index
            window.addItem(entry)
        }
        NSApp.windowsMenu = window

        return main
    }

    /// Translation commands, used in the menu bar and in each window's Translate button.
    static func translateItems(target: AppDelegate, shortcuts: Bool, missing: [Locale.Language]) -> [NSMenuItem] {
        let chat = item("Translate This Chat", #selector(AppDelegate.toggleChatTranslation(_:)),
                        shortcuts ? "t" : "", [.command, .shift], target)
        let mine = item("Translate My Message…", #selector(AppDelegate.translateMyMessage(_:)),
                        shortcuts ? "m" : "", [.command, .shift], target)
        let notifications = item("Translate Notifications", #selector(AppDelegate.toggleNotificationTranslation(_:)),
                                 "", [], target)

        let into = NSMenuItem(title: "Translate Into", action: nil, keyEquivalent: "")
        let languages = NSMenu(title: "Translate Into")
        let mac = Locale.current.language
        let system = item("My Mac's Language (\(Translator.displayName(mac)))",
                          #selector(AppDelegate.setTranslateTarget(_:)), "", [], target)
        system.representedObject = ""
        languages.addItem(system)
        languages.addItem(.separator())
        for code in Translator.commonLanguages {
            let entry = item(Translator.displayName(Locale.Language(identifier: code)),
                             #selector(AppDelegate.setTranslateTarget(_:)), "", [], target)
            entry.representedObject = code
            languages.addItem(entry)
        }
        into.submenu = languages

        // Languages seen in messages that aren't downloaded yet. Downloading only starts here.
        let downloads = missing.sorted { Translator.displayName($0) < Translator.displayName($1) }.map { language in
            let entry = item("Download \(Translator.displayName(language)) for Translation…",
                             #selector(AppDelegate.downloadLanguage(_:)), "", [], target)
            entry.representedObject = language.languageCode?.identifier
            return entry
        }

        return [chat, mine, .separator(), notifications, into] + (downloads.isEmpty ? [] : [.separator()] + downloads)
    }

    private static func submenu(in main: NSMenu, title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = menu
        main.addItem(holder)
        return menu
    }

    private static func item(_ title: String, _ action: Selector, _ key: String,
                             _ modifiers: NSEvent.ModifierFlags, _ target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }
}
