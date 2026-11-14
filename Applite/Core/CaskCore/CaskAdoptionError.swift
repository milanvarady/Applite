import Foundation

enum CaskAdoptionError: LocalizedError {
    case notManaged
    case appStoreManaged
    case intuneManaged
    case intuneInventoryUnavailable
    case setappManaged
    case artCraftManaged
    case artCraftInventoryUnavailable
    case homebrewUnavailable
    case homebrewDisabled
    case notHomebrewManaged
    case configurationChanged
    case confirmationRequired
    case confirmationExpired
    case installationTargetsUnavailable

    var errorDescription: String? {
        switch self {
        case .notManaged:
            String(localized: "Homebrew finished installing, but the app is not listed as managed. Refresh the app catalog to check again.")
        case .appStoreManaged:
            String(localized: "This app is managed by the App Store. Use the App Store for updates; Homebrew management is disabled.")
        case .intuneManaged:
            String(localized: "Your organization manages this app through Microsoft Intune (Company Portal). Use Company Portal or contact your IT administrator; Homebrew management is disabled.")
        case .intuneInventoryUnavailable:
            String(localized: "Couldn't verify Intune app ownership. Homebrew changes are blocked. Sync Company Portal and try again, or contact your IT administrator.")
        case .setappManaged:
            String(localized: "This app is managed by Setapp. Use Setapp for updates; Homebrew management is disabled.")
        case .artCraftManaged:
            String(localized: "This app is managed by ArtCraft Launcher. Use ArtCraft Launcher for updates; Homebrew management is disabled.")
        case .artCraftInventoryUnavailable:
            String(localized: "Couldn't verify ArtCraft Launcher app ownership. Homebrew changes are blocked. Check ArtCraft Launcher and try again.")
        case .homebrewUnavailable:
            String(localized: "This app is not available as an exact cask in the selected Homebrew. Applite cannot manage it. Refresh the app catalog to check again.")
        case .homebrewDisabled:
            String(localized: "Homebrew has disabled this cask. Applite cannot install, adopt, update, or reinstall it.")
        case .notHomebrewManaged:
            String(localized: "This app is not installed through the selected Homebrew. Applite cannot uninstall it.")
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
