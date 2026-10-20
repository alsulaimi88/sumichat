import Foundation
import WebKit

/// A linked WhatsApp account. The primary account uses the default web data store, so the
/// login from before SumiChat had accounts keeps working; every other account gets its own
/// store, which keeps its login, cookies and cache separate.
struct Account: Codable, Equatable {
    var id: UUID
    var name: String
    var isPrimary: Bool

    @MainActor var dataStore: WKWebsiteDataStore {
        if !isPrimary {
            if #available(macOS 14.0, *) { return WKWebsiteDataStore(forIdentifier: id) }
        }
        return .default()
    }
}

enum AccountList {
    private static let key = "Accounts"

    /// Separate logins need per-account data stores, which arrived in macOS 14.
    static var supportsMultiple: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }

    static func load() -> [Account] {
        if let data = UserDefaults.standard.data(forKey: key),
           let accounts = try? JSONDecoder().decode([Account].self, from: data),
           !accounts.isEmpty {
            return supportsMultiple ? accounts : accounts.filter(\.isPrimary)
        }
        return [Account(id: UUID(), name: "Main", isPrimary: true)]
    }

    static func save(_ accounts: [Account]) {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
