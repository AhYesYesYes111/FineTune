// FineTune/Utilities/UpdateManager.swift
import Foundation
import Combine
#if !FINETUNE_FORK_BUILD
import Sparkle
#endif

/// Official builds use Sparkle; fork builds use manual downloads.
@MainActor
final class UpdateManager: NSObject, ObservableObject {
    @Published var canCheckForUpdates = false

    #if FINETUNE_FORK_BUILD
    // Do not reference Sparkle in fork binaries: these builds have no update
    // feed and must not depend on its separately signed framework at runtime.
    static let isEnabled = false

    func checkForUpdates() {}

    var automaticallyChecksForUpdates: Bool {
        get { false }
        set {}
    }

    var automaticallyDownloadsUpdates: Bool {
        get { false }
        set {}
    }

    var lastUpdateCheckDate: Date? { nil }
    #else
    static let isEnabled = true

    private let updaterController: SPUStandardUpdaterController

    override init() {
        // Create the updater controller without auto-starting (prevents popup on launch)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()

        // Start updater to enable manual checks, but don't trigger auto-check UI
        try? updaterController.updater.start()

        // Observe when updates can be checked
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// Check for updates manually
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// Whether automatic update checks are enabled
    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Whether to automatically download updates
    var automaticallyDownloadsUpdates: Bool {
        get { updaterController.updater.automaticallyDownloadsUpdates }
        set { updaterController.updater.automaticallyDownloadsUpdates = newValue }
    }

    /// Last update check date
    var lastUpdateCheckDate: Date? {
        updaterController.updater.lastUpdateCheckDate
    }
    #endif
}
