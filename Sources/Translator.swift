import AppKit
import NaturalLanguage
import SwiftUI
import Translation

/// On-device translation with Apple's Translation framework (macOS 26+): messages never
/// leave the Mac. Languages are handled by name only ("English", "Arabic"): whichever
/// version of a language this Mac has downloaded (UK, US, …) is the one used. Downloads
/// only start when the user asks for them.
@MainActor
final class Translator {
    enum Outcome {
        case translated(String)
        case sameLanguage                   // already in the target language, or too short to tell
        case needsDownload(Locale.Language) // the language (not ours) that isn't downloaded
        case unsupported
        case failed
    }

    enum DownloadResult { case ready, waiting, cancelled }

    static var isAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    // MARK: Settings

    private static let targetKey = "TranslateTo"
    private static let notificationsKey = "TranslateNotifications"

    /// Language code translations go into ("en", "ar", …); nil means the Mac's own language.
    static var targetCode: String? {
        get { UserDefaults.standard.string(forKey: targetKey) }
        set { UserDefaults.standard.set(newValue, forKey: targetKey) }
    }

    static var targetLanguage: Locale.Language {
        Locale.Language(identifier: targetCode ?? myLanguage.languageCode?.identifier ?? "en")
    }

    /// The language last used for "Translate My Message", when a chat's language is unclear.
    static var lastReplyCode: String? {
        get { UserDefaults.standard.string(forKey: "LastReplyLanguage") }
        set { UserDefaults.standard.set(newValue, forKey: "LastReplyLanguage") }
    }

    static var translatesNotifications: Bool {
        get { UserDefaults.standard.object(forKey: notificationsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: notificationsKey) }
    }

    /// Choices for "Translate Into" and for replies.
    static let commonLanguages = ["en", "ar", "fr", "de", "es", "it", "pt", "nl", "ru", "tr",
                                  "zh", "ja", "ko", "hi", "id", "th", "vi", "pl", "uk"]

    // MARK: Languages

    private static var myLanguage: Locale.Language { Locale.current.language }

    /// "English", "Arabic": the language alone, never its region.
    static func displayName(_ language: Locale.Language) -> String {
        let code = language.languageCode?.identifier ?? language.minimalIdentifier
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    static func sameLanguage(_ a: Locale.Language, _ b: Locale.Language) -> Bool {
        a.languageCode == b.languageCode
    }

    /// Of a translation pair, the language that isn't the Mac's own (what gets downloaded).
    static func foreign(_ source: Locale.Language, _ target: Locale.Language) -> Locale.Language {
        sameLanguage(source, myLanguage) ? target : source
    }

    /// Best guess at the language of `text`, or nil when it's too short or unclear to say.
    static func detectLanguage(_ text: String) -> Locale.Language? {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letters >= 6 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              language != .undetermined, confidence >= 0.6 else { return nil }
        return Locale.Language(identifier: language.rawValue)
    }

    // MARK: Finding a downloaded version

    private var supported: [Locale.Language]?
    private var installedPairs: [String: (Locale.Language, Locale.Language)] = [:]

    private static func key(_ source: Locale.Language, _ target: Locale.Language) -> String {
        "\(source.languageCode?.identifier ?? "?")>\(target.languageCode?.identifier ?? "?")"
    }

    /// The language as given, the Mac's own versions of it, then every version macOS supports.
    private func versions(of language: Locale.Language) async -> [Locale.Language] {
        guard #available(macOS 26.0, *) else { return [language] }
        if supported == nil { supported = await LanguageAvailability().supportedLanguages }
        let mine = [Self.myLanguage] + Locale.preferredLanguages.map { Locale.Language(identifier: $0) }
        var seen = Set<String>()
        return ([language] + mine + (supported ?? []))
            .filter { Self.sameLanguage($0, language) }
            .filter { seen.insert($0.maximalIdentifier).inserted }
    }

    /// Looks for any downloaded version of source → target, e.g. German → English (UK)
    /// when US English isn't downloaded.
    @available(macOS 26.0, *)
    private func usablePair(_ source: Locale.Language, _ target: Locale.Language) async
        -> (source: Locale.Language, target: Locale.Language, status: LanguageAvailability.Status) {
        let key = Self.key(source, target)
        if let pair = installedPairs[key] { return (pair.0, pair.1, .installed) }
        let availability = LanguageAvailability()
        var best = LanguageAvailability.Status.unsupported
        for s in await versions(of: source) {
            for t in await versions(of: target) {
                let status = await availability.status(from: s, to: t)
                if status == .installed {
                    installedPairs[key] = (s, t)
                    return (s, t, .installed)
                }
                if status == .supported { best = .supported }
            }
        }
        return (source, target, best)
    }

    // MARK: Translating

    private var sessions: [String: AnyObject] = [:]
    private var cache: [String: String] = [:]

    /// Languages found in messages that can't be translated until they're downloaded.
    private(set) var missingLanguages: [String: Locale.Language] = [:]
    /// Called when that list changes (to update the Download menu items).
    var onMissingLanguagesChanged: (() -> Void)?
    /// A language became usable: translations can be redone.
    var onLanguageReady: ((Locale.Language) -> Void)?

    /// Translates into `target`, or into the chosen "Translate Into" language when nil.
    func translate(_ text: String, from source: Locale.Language? = nil,
                   to target: Locale.Language? = nil) async -> Outcome {
        guard #available(macOS 26.0, *) else { return .unsupported }
        let target = target ?? Self.targetLanguage
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let source = source ?? Self.detectLanguage(text) else { return .sameLanguage }
        if Self.sameLanguage(source, target) { return .sameLanguage }

        let key = Self.key(source, target)
        if let cached = cache["\(key)|\(text)"] { return .translated(cached) }

        let pair = await usablePair(source, target)
        switch pair.status {
        case .installed: break
        case .supported:
            let language = Self.foreign(source, target)
            if missingLanguages.updateValue(language, forKey: language.languageCode?.identifier ?? "?") == nil {
                onMissingLanguagesChanged?()
            }
            return .needsDownload(language)
        default: return .unsupported
        }

        let session = (sessions[key] as? TranslationSession) ?? {
            let session = TranslationSession(installedSource: pair.source, target: pair.target)
            sessions[key] = session
            return session
        }()
        do {
            let result = try await session.translate(text).targetText
            cache["\(key)|\(text)"] = result
            return .translated(result)
        } catch {
            NSLog("SumiChat: translation \(key) failed: \(error.localizedDescription)")
            sessions[key] = nil
            installedPairs[key] = nil
            return .failed
        }
    }

    // MARK: Downloading (only when asked)

    private var watching: Set<String> = []

    /// Shows macOS's own download prompt for `language` (with the translation target, or
    /// the Mac's language). Returns .ready if it's usable right away; .waiting if macOS may
    /// still be downloading it, in which case `onLanguageReady` fires when it's done.
    @discardableResult
    func download(_ language: Locale.Language, pairedWith other: Locale.Language? = nil,
                  over window: NSWindow?) async -> DownloadResult {
        guard #available(macOS 26.0, *) else { return .cancelled }
        var partner = other ?? Self.targetLanguage
        if Self.sameLanguage(partner, language) { partner = Self.myLanguage }
        // Ask for the Mac's own version of its language, so the right English (or Arabic) is used.
        let asLocal: (Locale.Language) -> Locale.Language = {
            Self.sameLanguage($0, Self.myLanguage) ? Self.myLanguage : Locale.Language(identifier: $0.languageCode?.identifier ?? $0.minimalIdentifier)
        }
        let source = asLocal(language), target = asLocal(partner)

        if await usablePair(source, target).status == .installed {
            languageBecameReady(language)
            return .ready
        }

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<DownloadResult, Never>) in
            var finished = false
            let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 150),
                                 styleMask: [.titled], backing: .buffered, defer: false)
            let finish: (DownloadResult) -> Void = { result in
                guard !finished else { return }
                finished = true
                if let parent = sheet.sheetParent { parent.endSheet(sheet) } else { sheet.close() }
                continuation.resume(returning: result)
            }
            sheet.contentViewController = NSHostingController(rootView: LanguageDownloadView(
                language: language, source: source, target: target, done: finish
            ))
            if let window {
                window.beginSheet(sheet)
            } else {
                sheet.center()
                sheet.makeKeyAndOrderFront(nil)
            }
        }

        switch result {
        case .ready:
            languageBecameReady(language)
        case .waiting:
            // If the user chose Download, macOS finishes it in the background; we just
            // watch quietly and say so when it's ready. If they didn't, nothing happens.
            Task { await watch(language, source, target) }
        case .cancelled:
            break
        }
        return result
    }

    private func watch(_ language: Locale.Language, _ source: Locale.Language, _ target: Locale.Language) async {
        guard #available(macOS 26.0, *) else { return }
        let id = Self.key(source, target)
        guard watching.insert(id).inserted else { return }
        defer { watching.remove(id) }
        for _ in 0..<600 { // up to 30 minutes
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if await usablePair(source, target).status == .installed {
                languageBecameReady(language)
                return
            }
        }
    }

    private func languageBecameReady(_ language: Locale.Language) {
        cache.removeAll()
        if missingLanguages.removeValue(forKey: language.languageCode?.identifier ?? "?") != nil {
            onMissingLanguagesChanged?()
        }
        onLanguageReady?(language)
    }
}

/// Asks macOS to download a language (macOS shows its own prompt), then checks briefly
/// whether it's ready.
@available(macOS 26.0, *)
private struct LanguageDownloadView: View {
    let language: Locale.Language
    let source: Locale.Language
    let target: Locale.Language
    let done: (Translator.DownloadResult) -> Void

    var body: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Getting \(Translator.displayName(language)) ready for translation…")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Translation happens on this Mac. Messages aren't sent anywhere.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Cancel") { done(.cancelled) }
        }
        .padding(22)
        .frame(width: 380)
        .translationTask(TranslationSession.Configuration(source: source, target: target)) { session in
            do {
                try await session.prepareTranslation()
            } catch {
                done(.cancelled)
                return
            }
            // prepareTranslation also returns when the prompt is just closed, so check.
            for _ in 0..<4 {
                if await LanguageAvailability().status(from: source, to: target) == .installed {
                    done(.ready)
                    return
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            done(.waiting)
        }
    }
}
