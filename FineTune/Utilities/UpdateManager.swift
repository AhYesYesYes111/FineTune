// FineTune/Utilities/UpdateManager.swift
import Foundation
import Combine
import Sparkle

/// Manages app updates via Sparkle
@MainActor
final class UpdateManager: NSObject, ObservableObject {
    #if FINETUNE_FORK_BUILD
    static let isEnabled = false
    #else
    static let isEnabled = true
    #endif

    private let updaterController: SPUStandardUpdaterController?

    @Published var canCheckForUpdates = false

    override init() {
        // Fork builds use manual downloads. Do not create Sparkle: a feed saved
        // in user defaults can override the one in Info.plist.
        guard Self.isEnabled else {
            updaterController = nil
            super.init()
            return
        }

        // Create the updater controller without auto-starting (prevents popup on launch)
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController = controller
        super.init()

        // Start updater to enable manual checks, but don't trigger auto-check UI
        try? controller.updater.start()

        // Observe when updates can be checked
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// Check for updates manually
    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    /// Whether automatic update checks are enabled
    var automaticallyChecksForUpdates: Bool {
        get { updaterController?.updater.automaticallyChecksForUpdates ?? false }
        set { updaterController?.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Whether to automatically download updates
    var automaticallyDownloadsUpdates: Bool {
        get { updaterController?.updater.automaticallyDownloadsUpdates ?? false }
        set { updaterController?.updater.automaticallyDownloadsUpdates = newValue }
    }

    /// Last update check date
    var lastUpdateCheckDate: Date? {
        updaterController?.updater.lastUpdateCheckDate
    }
}
