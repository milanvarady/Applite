import Foundation

struct ProtectedAppInstallation: Equatable, Sendable {
    enum Source: CaseIterable, Hashable, Sendable {
        case intune
        case appStore
        case setapp
        case artCraft

        var name: String {
            switch self {
            case .intune: String(localized: "Microsoft Intune (Company Portal)")
            case .appStore: String(localized: "Apple App Store")
            case .setapp: String(localized: "Setapp")
            case .artCraft: String(localized: "ArtCraft Launcher")
            }
        }

        var overrideTitle: String {
            switch self {
            case .intune: String(localized: "Override Microsoft Intune protection")
            case .appStore: String(localized: "Override Apple App Store protection")
            case .setapp: String(localized: "Override Setapp protection")
            case .artCraft: String(localized: "Override ArtCraft Launcher protection")
            }
        }

        var overridePreference: PreferenceKey<Bool> {
            switch self {
            case .intune: Preferences.overrideIntuneManagement
            case .appStore: Preferences.overrideAppStoreManagement
            case .setapp: Preferences.overrideSetappManagement
            case .artCraft: Preferences.overrideArtCraftManagement
            }
        }

        static func enabledOverrides(in defaults: UserDefaults = .standard) -> Set<Self> {
            guard defaults.value(for: Preferences.detectExternallyInstalledApps),
                  defaults.value(for: Preferences.offerHomebrewManagement) else { return [] }
            return Set(allCases.filter { defaults.value(for: $0.overridePreference) })
        }

        var displayName: String {
            switch self {
            case .intune: String(localized: "Intune-managed")
            case .appStore: String(localized: "App Store-managed")
            case .setapp: String(localized: "Setapp-managed")
            case .artCraft: String(localized: "ArtCraft-managed")
            }
        }

        var blockError: CaskAdoptionError {
            switch self {
            case .intune: .intuneManaged
            case .appStore: .appStoreManaged
            case .setapp: .setappManaged
            case .artCraft: .artCraftManaged
            }
        }
    }

    let url: URL
    let source: Source
    let appURLs: [Source: URL]

    init(url: URL, source: Source) {
        self.url = url
        self.source = source
        self.appURLs = [source: url]
    }

    init?(appURLs: [Source: URL]) {
        guard let source = Source.allCases.first(where: { appURLs[$0] != nil }),
              let url = appURLs[source] else { return nil }
        self.url = url
        self.source = source
        self.appURLs = appURLs
    }

    func excluding(_ overrides: Set<Source>) -> Self? {
        Self(appURLs: appURLs.filter { !overrides.contains($0.key) })
    }
}
