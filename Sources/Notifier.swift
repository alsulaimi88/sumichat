import AppKit
import UserNotifications

/// Shows macOS notifications for new messages (with a Reply box) and finished downloads.
@MainActor
final class Notifier: NSObject {
    /// A message notification was clicked: (account, the shim's notification id).
    var onMessageClick: ((UUID, String) -> Void)?
    /// A reply was typed into a notification: (account, notification id, chat name, text).
    /// Returns the page's answer, "sent" on success.
    var onReply: ((UUID, String, String, String) async -> String)?

    /// Account names, shown under the title once there's more than one account.
    var accountNames: [UUID: String] = [:]
    var showsAccountNames = false

    private static let messageCategory = "message"
    private static let replyAction = "reply"

    private var center: UNUserNotificationCenter { .current() }

    func setUp() {
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.messageCategory,
                actions: [UNTextInputNotificationAction(
                    identifier: Self.replyAction, title: "Reply", options: [],
                    textInputButtonTitle: "Send", textInputPlaceholder: "Message"
                )],
                intentIdentifiers: []
            ),
        ])
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                NSLog("SumiChat: notification permission error: \(error.localizedDescription)")
            } else if !granted {
                NSLog("SumiChat: notifications are turned off in System Settings")
            }
        }
    }

    func showMessage(accountID: UUID, id: String, title: String, body: String, tag: String, silent: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if showsAccountNames, let name = accountNames[accountID] { content.subtitle = name }
        if !silent { content.sound = .default }
        if !tag.isEmpty { content.threadIdentifier = "\(accountID.uuidString)-\(tag)" } // groups messages per chat
        content.categoryIdentifier = Self.messageCategory
        content.userInfo = ["kind": "message", "account": accountID.uuidString, "id": id, "title": title]
        post(content, identifier: "message-\(accountID.uuidString)-\(id)")
    }

    func showDownloadFinished(_ file: URL) {
        let content = UNMutableNotificationContent()
        content.title = "Saved to Downloads"
        content.body = file.lastPathComponent
        content.userInfo = ["kind": "download", "path": file.path]
        post(content, identifier: "download-\(UUID().uuidString)")
    }

    func showDownloadFailed(name: String?, error: Error) {
        let content = UNMutableNotificationContent()
        content.title = "Download failed"
        content.body = [name, error.localizedDescription].compactMap { $0 }.joined(separator: " — ")
        post(content, identifier: "download-\(UUID().uuidString)")
    }

    /// The reply couldn't be sent safely. Keep the text on the clipboard and say so;
    /// clicking this opens the chat.
    private func showReplyFailed(accountID: UUID, id: String, chat: String, text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        let content = UNMutableNotificationContent()
        content.title = "Reply not sent"
        content.body = "Couldn't send to \(chat). Your message is copied. Click to open the chat and paste it."
        content.sound = .default
        content.userInfo = ["kind": "message", "account": accountID.uuidString, "id": id, "title": chat]
        post(content, identifier: "reply-failed-\(UUID().uuidString)")
    }

    private func post(_ content: UNNotificationContent, identifier: String) {
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil)) { error in
            if let error { NSLog("SumiChat: could not show notification: \(error.localizedDescription)") }
        }
    }

    fileprivate func handle(kind: String?, account: String?, id: String?, title: String?, path: String?,
                            replyText: String?) async {
        if kind == "download", let path {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            return
        }
        guard kind == "message", let id, let accountID = account.flatMap(UUID.init(uuidString:)) else { return }

        if let replyText {
            let chat = title ?? "this chat"
            let answer = await onReply?(accountID, id, chat, replyText) ?? "no-account"
            if answer != "sent" {
                NSLog("SumiChat: reply to \(chat) not sent (\(answer))")
                showReplyFailed(accountID: accountID, id: id, chat: chat, text: replyText)
            }
        } else {
            onMessageClick?(accountID, id)
        }
    }
}

extension Notifier: UNUserNotificationCenterDelegate {
    /// Show banners even while the app is open (WhatsApp only notifies when you're not looking at the chat).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        guard response.actionIdentifier != UNNotificationDismissActionIdentifier else {
            completionHandler()
            return
        }
        let info = response.notification.request.content.userInfo
        let kind = info["kind"] as? String
        let account = info["account"] as? String
        let id = info["id"] as? String
        let title = info["title"] as? String
        let path = info["path"] as? String
        let replyText = (response as? UNTextInputNotificationResponse)?.userText
        Task { @MainActor in
            await self.handle(kind: kind, account: account, id: id, title: title, path: path, replyText: replyText)
            completionHandler()
        }
    }
}
