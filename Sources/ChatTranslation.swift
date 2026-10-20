import AppKit
import WebKit

/// "Translate This Chat" and "Translate My Message" for one account's web view.
extension BrowserController {
    /// Turns translations under each message on or off for the open chat (and the chats you open next).
    func setChatTranslation(_ on: Bool) {
        isTranslatingChat = on
        webView.evaluateJavaScript("window.__sumiSetChatTranslation && window.__sumiSetChatTranslation(\(on))")
    }

    /// Called with message texts the page hasn't seen yet; sends back their translations.
    /// A language that isn't downloaded gets a short note instead (and a Download item in the
    /// Translate menu); nothing is downloaded unless the user picks that item.
    func translateChatMessages(_ texts: [String]) async {
        var results: [[String: Any]] = []
        for text in texts {
            switch await translator.translate(text) {
            case .translated(let translation):
                results.append(["text": text, "translation": translation])
            case .needsDownload(let language):
                results.append(["text": text, "missing": Translator.displayName(language)])
            default:
                results.append(["text": text, "translation": NSNull()])
            }
        }
        await send(results)
    }

    private func send(_ results: [[String: Any]]) async {
        guard !results.isEmpty else { return }
        _ = try? await webView.callAsyncJavaScript("window.__sumiShowTranslations(items)", arguments: ["items": results],
                                                   in: nil, contentWorld: .page)
    }

    /// Translates what's typed in the message box into the language the other person writes in,
    /// shows it for checking, and only then puts it in the message box. Nothing is sent.
    func translateMyMessage() async {
        let typed = (try? await webView.callAsyncJavaScript("return window.__sumiComposerText()", arguments: [:],
                                                            in: nil, contentWorld: .page)) as? String
        guard let typed, !typed.isEmpty else {
            alert("Type your message first",
                  "Write your reply in the message box in your own language, then choose Translate My Message.")
            return
        }
        let recent = (try? await webView.callAsyncJavaScript("return window.__sumiRecentMessages()", arguments: [:],
                                                             in: nil, contentWorld: .page)) as? [String] ?? []
        let source = Translator.detectLanguage(typed) ?? Translator.targetLanguage
        let chatLanguage = Self.chatLanguage(of: recent, other: source)
            ?? Translator.lastReplyCode.map { Locale.Language(identifier: $0) }

        let picker = ReplyTranslationPanel(original: typed, source: source, suggested: chatLanguage,
                                           translator: translator, window: webView.window)
        guard let translation = await picker.run() else { return }
        if let chosen = picker.chosenLanguage { Translator.lastReplyCode = chosen.languageCode?.identifier }
        let replaced = (try? await webView.callAsyncJavaScript("return await window.__sumiReplaceComposer(text)",
                                                               arguments: ["text": translation],
                                                               in: nil, contentWorld: .page)) as? Bool ?? false
        if !replaced {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(translation, forType: .string)
            alert("Translation copied", "Couldn't put it in the message box, so it's on the clipboard. Paste it with ⌘V.")
        }
    }

    /// The language most of the chat's recent messages (from either side) are in, other than
    /// the one you're typing in. Both people often write in the guest's language.
    private static func chatLanguage(of messages: [String], other mine: Locale.Language) -> Locale.Language? {
        var counts: [String: (language: Locale.Language, count: Int)] = [:]
        for message in messages {
            guard let language = Translator.detectLanguage(message), !Translator.sameLanguage(language, mine),
                  let code = language.languageCode?.identifier else { continue }
            counts[code, default: (language, 0)].count += 1
        }
        return counts.values.max { $0.count < $1.count }?.language
    }

    private func alert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        if let window = webView.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

/// The "Translate My Message" sheet: pick the language, check (and edit) the translation,
/// then use it or cancel.
@MainActor
private final class ReplyTranslationPanel: NSObject {
    private let original: String
    private let source: Locale.Language
    private let translator: Translator
    private weak var window: NSWindow?
    private let languages: [Locale.Language]

    private let popup = NSPopUpButton()
    private let textView = NSTextView()
    private let status = NSTextField(labelWithString: "")
    private let downloadButton = NSButton()
    private var missingLanguage: Locale.Language?
    /// The language picked when "Use Translation" was clicked.
    private(set) var chosenLanguage: Locale.Language?
    private var alert: NSAlert?
    private var translateTask: Task<Void, Never>?

    init(original: String, source: Locale.Language, suggested: Locale.Language?, translator: Translator, window: NSWindow?) {
        self.original = original
        self.source = source
        self.translator = translator
        self.window = window
        var languages = Translator.commonLanguages.map { Locale.Language(identifier: $0) }
            .filter { !Translator.sameLanguage($0, source) }
        if let suggested, !languages.contains(where: { Translator.sameLanguage($0, suggested) }) {
            languages.insert(suggested, at: 0)
        }
        self.languages = languages
        super.init()
        for language in languages { popup.addItem(withTitle: Translator.displayName(language)) }
        if let suggested, let index = languages.firstIndex(where: { Translator.sameLanguage($0, suggested) }) {
            popup.selectItem(at: index)
        }
        popup.target = self
        popup.action = #selector(languageChanged)
    }

    /// Returns the translation to use, or nil if cancelled.
    func run() async -> String? {
        let alert = NSAlert()
        self.alert = alert
        alert.messageText = "Translate my message"
        alert.informativeText = "Check the translation before using it. You can edit it here. It goes into the message box; you still press Send yourself."
        alert.addButton(withTitle: "Use Translation")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = makeAccessory()
        languageChanged()

        let response: NSApplication.ModalResponse
        if let window {
            response = await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            }
        } else {
            response = alert.runModal()
        }
        translateTask?.cancel()
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard response == .alertFirstButtonReturn, !text.isEmpty else { return nil }
        chosenLanguage = languages[max(0, popup.indexOfSelectedItem)]
        return text
    }

    private func makeAccessory() -> NSView {
        let width: CGFloat = 380
        let label = NSTextField(labelWithString: "Into:")
        let row = NSStackView(views: [label, popup])
        row.spacing = 8

        textView.isRichText = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: 110))
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        textView.frame = NSRect(x: 0, y: 0, width: width, height: 110)

        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.textColor = .secondaryLabelColor
        downloadButton.bezelStyle = .push
        downloadButton.controlSize = .small
        downloadButton.target = self
        downloadButton.action = #selector(downloadMissing)
        downloadButton.isHidden = true
        let statusRow = NSStackView(views: [status, downloadButton])
        statusRow.spacing = 8

        let original = NSTextField(wrappingLabelWithString: "Your message: \(self.original)")
        original.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        original.textColor = .secondaryLabelColor
        original.preferredMaxLayoutWidth = width

        let stack = NSStackView(views: [row, scroll, statusRow, original])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: width, height: 210)
        NSLayoutConstraint.activate([
            scroll.widthAnchor.constraint(equalToConstant: width),
            scroll.heightAnchor.constraint(equalToConstant: 110),
        ])
        return stack
    }

    /// Only runs when the user clicks "Download …".
    @objc private func downloadMissing() {
        guard let language = missingLanguage else { return }
        let target = languages[max(0, popup.indexOfSelectedItem)]
        Task { [weak self] in
            guard let self else { return }
            let partner = Translator.sameLanguage(language, target) ? source : target
            switch await translator.download(language, pairedWith: partner, over: alert?.window) {
            case .ready:
                languageChanged()
            case .waiting:
                status.stringValue = "If you chose Download, SumiChat will tell you when \(Translator.displayName(language)) is ready."
                downloadButton.isHidden = true
            case .cancelled:
                break
            }
        }
    }

    @objc private func languageChanged() {
        let target = languages[max(0, popup.indexOfSelectedItem)]
        translateTask?.cancel()
        textView.string = ""
        status.stringValue = "Translating…"
        downloadButton.isHidden = true
        missingLanguage = nil
        translateTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await translator.translate(original, from: source, to: target)
            guard !Task.isCancelled else { return }
            switch outcome {
            case .translated(let text):
                textView.string = text
                status.stringValue = "\(Translator.displayName(source)) → \(Translator.displayName(target)), translated on this Mac"
            case .sameLanguage:
                textView.string = original
                status.stringValue = "Your message is already in \(Translator.displayName(target))."
            case .needsDownload(let language):
                let name = Translator.displayName(language)
                status.stringValue = "\(name) isn't downloaded on this Mac yet."
                missingLanguage = language
                downloadButton.title = "Download \(name)"
                downloadButton.isHidden = false
            case .unsupported:
                status.stringValue = "This language pair can't be translated on this Mac."
            case .failed:
                status.stringValue = "Translation didn't work. Try again."
            }
        }
    }
}
