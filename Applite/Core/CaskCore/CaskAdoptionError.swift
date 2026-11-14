import Foundation

enum CaskAdoptionError: LocalizedError {
    case notManaged
    case configurationChanged
    case confirmationRequired
    case confirmationExpired
    case installationTargetsUnavailable

    var errorDescription: String? {
        switch self {
        case .notManaged:
            String(localized: "Homebrew finished installing, but the app is not listed as managed. Refresh the app catalog to check again.")
        case .configurationChanged:
            String(localized: "Homebrew or the app installation directory changed. Review the current settings and confirm the command again.")
        case .confirmationRequired:
            String(localized: "This app is already installed. Enable Homebrew management and confirm the current command before reinstalling it.")
        case .confirmationExpired:
            String(localized: "This Homebrew management confirmation expired. Review and confirm the current command again.")
        case .installationTargetsUnavailable:
            String(localized: "Couldn't verify this cask's installation targets. Homebrew changes are blocked. Refresh the app catalog and try again.")
        }
    }
}
