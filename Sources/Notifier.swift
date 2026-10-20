import AppKit
import UserNotifications

/// Shows macOS notifications for new messages and finished downloads.
@MainActor
final class Notifier: NSObject {
    /// Called with the shim's notification id when a message notification is clicked.
    var onMessageClick: ((String) -> Void)?

    private var center: UNUserNotificationCenter { .current() }

    func setUp() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                NSLog("SumiChat: notification permission error: \(error.localizedDescription)")
            } else if !granted {
                NSLog("SumiChat: notifications are turned off in System Settings")
            }
        }
    }

    func showMessage(id: String, title: String, body: String, tag: String, silent: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if !silent { content.sound = .default }
        if !tag.isEmpty { content.threadIdentifier = tag } // groups messages per chat
        content.userInfo = ["kind": "message", "id": id]
        post(content, identifier: "message-\(id)")
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

    private func post(_ content: UNNotificationContent, identifier: String) {
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil)) { error in
            if let error { NSLog("SumiChat: could not show notification: \(error.localizedDescription)") }
        }
    }

    fileprivate func handleClick(kind: String?, id: String?, path: String?) {
        if kind == "download", let path {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else if kind == "message", let id {
            onMessageClick?(id)
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
        let info = response.notification.request.content.userInfo
        let kind = info["kind"] as? String
        let id = info["id"] as? String
        let path = info["path"] as? String
        Task { @MainActor in
            self.handleClick(kind: kind, id: id, path: path)
        }
        completionHandler()
    }
}
