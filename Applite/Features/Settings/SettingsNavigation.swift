import Observation

@MainActor
@Observable
final class SettingsNavigation {
    enum Pane: Hashable {
        case general, apps, brew, updates, proxy, mirrors, uninstall
    }

    var selection: Pane = .general

    func showUninstall(openSettings: () -> Void) {
        selection = .uninstall
        openSettings()
    }

    func showUpdates(openSettings: () -> Void, checkForUpdates: () -> Void) {
        selection = .updates
        openSettings()
        checkForUpdates()
    }
}
