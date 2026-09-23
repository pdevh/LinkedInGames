import AppKit
import Sparkle

/// Keeps Sparkle alive for the process lifetime. Sparkle owns download,
/// signature verification, installation prompts, and relaunch.
final class UpdateService {
    static let shared = UpdateService()

    private let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    private init() {}

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func checkForUpdatesInBackground() {
        guard automaticallyChecksForUpdates else { return }
        controller.updater.checkForUpdatesInBackground()
    }
}
