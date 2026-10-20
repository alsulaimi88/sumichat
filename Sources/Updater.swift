import AppKit

/// Checks GitHub for a newer release once a day, and from "Check for Updates…".
@MainActor
final class Updater {
    static let repository = "alsulaimi88/sumichat"
    static let installerURL = URL(string: "https://github.com/\(repository)/releases/latest/download/SumiChat.pkg")!

    private static let lastCheckKey = "LastUpdateCheck"

    private struct Release: Decodable {
        let tagName: String
        enum CodingKeys: String, CodingKey { case tagName = "tag_name" }
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func checkIfDue() {
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        if Date().timeIntervalSince1970 - last > 24 * 60 * 60 {
            check(userInitiated: false)
        }
    }

    func check(userInitiated: Bool) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let latest = try JSONDecoder().decode(Release.self, from: data).tagName
                    .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                if Self.isVersion(latest, newerThan: currentVersion) {
                    offerUpdate(to: latest)
                } else if userInitiated {
                    showAlert("You're up to date", "SumiChat \(currentVersion) is the latest version.")
                }
            } catch {
                if userInitiated {
                    showAlert("Couldn't check for updates", "Check your internet connection and try again.")
                }
            }
        }
    }

    private func offerUpdate(to version: String) {
        let alert = NSAlert()
        alert.messageText = "SumiChat \(version) is available"
        alert.informativeText = "You have version \(currentVersion). Download the installer and open it to update. Your chats stay signed in."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(Self.installerURL)
        }
    }

    private func showAlert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }

    /// "1.10" is newer than "1.9"; missing parts count as 0.
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}
