import AppKit
import WebKit

/// Owns the WKWebView that shows WhatsApp Web and handles everything the page
/// asks of the "browser": downloads, file pickers, mic/camera, popups and
/// notifications.
@MainActor
final class BrowserController: NSObject {
    static let home = URL(string: "https://web.whatsapp.com/")!

    /// WhatsApp Web only runs in browsers it recognises, so present as Safari.
    static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"

    let webView: WKWebView
    let accountID: UUID
    var onUnreadCountChange: ((Int) -> Void)?

    private let notifier: Notifier
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]
    private var titleObservation: NSKeyValueObservation?

    init(account: Account, notifier: Notifier) {
        self.notifier = notifier
        accountID = account.id

        let contentController = WKUserContentController()
        contentController.addUserScript(WKUserScript(
            source: NotificationShim.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        let config = WKWebViewConfiguration()
        config.websiteDataStore = account.dataStore // keeps this account logged in between launches
        config.userContentController = contentController
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true

        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = Self.safariUserAgent
        webView.allowsMagnification = true
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        super.init()

        contentController.add(self, name: "notify")
        webView.navigationDelegate = self
        webView.uiDelegate = self

        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
            let title = webView.title ?? ""
            DispatchQueue.main.async { self?.titleChanged(title) }
        }
    }

    func load() {
        webView.load(URLRequest(url: Self.home))
    }

    func reload() {
        if webView.url == nil {
            load()
        } else {
            webView.reload()
        }
    }

    /// Stops the page and lets go of everything, so the account's data can be deleted.
    func tearDown() {
        titleObservation = nil
        webView.stopLoading()
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.loadHTMLString("", baseURL: nil)
    }

    func notificationClicked(id: String) {
        guard let data = try? JSONEncoder().encode(id), let literal = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.__sumiNotificationClick && window.__sumiNotificationClick(\(literal))")
    }

    /// Sends `text` to the chat a notification came from, without bringing the window forward.
    /// The page opens that chat and only sends if its name matches `chatTitle`; otherwise
    /// nothing is sent. Returns the page's answer: "sent" on success.
    func reply(toNotification id: String, chatTitle: String, text: String) async -> String {
        do {
            let result = try await webView.callAsyncJavaScript(
                "return await window.__sumiReply(id, title, text);",
                arguments: ["id": id, "title": chatTitle, "text": text],
                in: nil,
                contentWorld: .page
            )
            return result as? String ?? "no-answer"
        } catch {
            NSLog("SumiChat: reply failed: \(error.localizedDescription)")
            return "error"
        }
    }

    /// WhatsApp puts the unread count in the page title, e.g. "(2) WhatsApp Business".
    private func titleChanged(_ title: String) {
        var count = 0
        if title.hasPrefix("("), let close = title.firstIndex(of: ")") {
            count = Int(title[title.index(after: title.startIndex)..<close]) ?? 0
        }
        onUnreadCountChange?(count)
    }

    private static func isWhatsApp(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return ["whatsapp.com", "whatsapp.net"].contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static func isAttachment(_ response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse,
              let disposition = http.value(forHTTPHeaderField: "Content-Disposition") else { return false }
        return disposition.lowercased().hasPrefix("attachment")
    }
}

// MARK: - Navigation

extension BrowserController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.allow)
            return
        }
        let inPage = ["http", "https", "blob", "data", "about"].contains(scheme)
        let externalLink = navigationAction.navigationType == .linkActivated && !Self.isWhatsApp(url.host)
        if !inPage || (externalLink && (scheme == "http" || scheme == "https")) {
            NSWorkspace.shared.open(url) // mailto:, tel:, and links people send you
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        if !navigationResponse.canShowMIMEType || Self.isAttachment(navigationResponse.response) {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        reload()
    }
}

// MARK: - Downloads (any file type, saved to ~/Downloads)

extension BrowserController: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping @MainActor @Sendable (URL?) -> Void) {
        let destination = Downloads.uniqueDestination(for: suggestedFilename)
        downloadDestinations[ObjectIdentifier(download)] = destination
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
        // Bounces the Downloads stack in the Dock, like Safari does.
        DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: url.path)
        notifier.showDownloadFinished(url)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let url = downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
        notifier.showDownloadFailed(name: url?.lastPathComponent, error: error)
    }
}

// MARK: - Page UI requests

extension BrowserController: WKUIDelegate {
    /// "Open" on a document, or a link with target=_blank.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        if url.scheme == "blob" || url.scheme == "data" {
            webView.startDownload(using: navigationAction.request) { [weak self] download in
                download.delegate = self
            }
        } else {
            NSWorkspace.shared.open(url)
        }
        return nil
    }

    /// Attaching photos and documents.
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        if let window = webView.window {
            panel.beginSheetModal(for: window) { result in
                completionHandler(result == .OK ? panel.urls : nil)
            }
        } else {
            completionHandler(panel.runModal() == .OK ? panel.urls : nil)
        }
    }

    /// Voice notes and calls.
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void) {
        decisionHandler(Self.isWhatsApp(origin.host) ? .grant : .deny)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping @MainActor @Sendable () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }
}

// MARK: - Messages from the notification shim

extension BrowserController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "notify",
              let body = message.body as? [String: Any],
              let id = body["id"] as? String else { return }
        notifier.showMessage(
            accountID: accountID,
            id: id,
            title: body["title"] as? String ?? "WhatsApp",
            body: body["body"] as? String ?? "",
            tag: body["tag"] as? String ?? "",
            silent: body["silent"] as? Bool ?? false
        )
    }
}

enum Downloads {
    static var folder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    /// ~/Downloads/name.pdf, or "name (1).pdf" etc. if that already exists.
    static func uniqueDestination(for suggestedFilename: String) -> URL {
        var name = suggestedFilename
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name.hasPrefix(".") { name = "WhatsApp file" + name }

        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            candidate = folder.appendingPathComponent(numbered)
            n += 1
        }
        return candidate
    }
}
