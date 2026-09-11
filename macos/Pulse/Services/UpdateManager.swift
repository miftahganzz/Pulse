import Foundation
import Combine
import Sparkle

@MainActor
public final class UpdateManager: ObservableObject {
    public static let shared = UpdateManager()

    private let updaterController: SPUStandardUpdaterController

    @Published public var canCheckForUpdates = false
    @Published public var automaticallyChecksForUpdates: Bool = true {
        didSet {
            updaterController.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    public var lastUpdateCheckDate: Date? {
        updaterController.updater.lastUpdateCheckDate
    }

    private init() {
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        self.automaticallyChecksForUpdates = self.updaterController.updater.automaticallyChecksForUpdates

        self.updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    public func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
