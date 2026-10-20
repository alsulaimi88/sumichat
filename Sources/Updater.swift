import AppKit
import Sparkle

/// Updates like VS Code: Sparkle checks the feed on the website (SUFeedURL) once a day and
/// downloads a new version quietly. When it's ready, the app shows a "Restart to Update"
/// button; clicking it installs and relaunches. Otherwise the update installs on quit.
/// Only updates signed with our key (SUPublicEDKey) and our Developer ID are accepted.
@MainActor
final class Updater: NSObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController!
    private var installNow: (() -> Void)?

    /// The version that's downloaded and waiting, if any.
    private(set) var readyVersion: String?
    var onUpdateReady: ((String) -> Void)?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func installAndRelaunch() {
        installNow?()
    }

    /// `SumiChat --check-for-updates` checks quietly at launch (used to test releases).
    func checkInBackgroundIfRequested() {
        if CommandLine.arguments.contains("--check-for-updates") {
            controller.updater.checkForUpdatesInBackground()
        }
    }

    // MARK: SPUUpdaterDelegate

    /// The update is downloaded and will install on quit; returning true means we show our
    /// own "Restart to Update" button instead of Sparkle's window.
    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                             immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        let version = item.displayVersionString
        DispatchQueue.main.async {
            NSLog("SumiChat: update \(version) downloaded and ready")
            self.installNow = immediateInstallHandler
            self.readyVersion = version
            self.onUpdateReady?(version)
        }
        return true
    }
}
