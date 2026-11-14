import SwiftUI

struct InstalledListOptions {
    enum SortOrder: String, CaseIterable, Identifiable {
        case aToZ
        case zToA
        case mostDownloaded

        var id: Self { self }

        var description: LocalizedStringKey {
            switch self {
            case .aToZ: "A to Z"
            case .zToA: "Z to A"
            case .mostDownloaded: "Most downloaded"
            }
        }
    }

    enum Source: String, CaseIterable, Identifiable {
        case all
        case homebrew
        case intune
        case appStore
        case setapp
        case artCraft
        case other

        var id: Self { self }

        var description: LocalizedStringKey {
            switch self {
            case .all: "All installed apps"
            case .homebrew: "Homebrew-managed"
            case .intune: "Intune-managed"
            case .appStore: "App Store-managed"
            case .setapp: "Setapp-managed"
            case .artCraft: "ArtCraft-managed"
            case .other: "Other installed apps"
            }
        }
    }

    var sortOrder: SortOrder = .aToZ
    var source: Source = .all
    var updatesOnly = false

    var hasFilters: Bool { source != .all || updatesOnly }

    @MainActor
    func apply(to casks: [CaskViewModel], query: String = "") -> [CaskViewModel] {
        let query = query.lowercased()
        return casks.filter { cask in
            let matchesSource = switch source {
            case .all: true
            case .homebrew: cask.isInstalled && !cask.isManagementProtected
            case .intune: cask.isIntuneManaged
            case .appStore: cask.isAppStoreManaged
            case .setapp: cask.isSetappManaged
            case .artCraft: cask.isArtCraftManaged
            case .other: cask.isInstalledExternally && cask.protectedAppInstallation == nil
            }
            return matchesSource
                && (!updatesOnly || cask.isOutdated)
                && (query.isEmpty || cask.name.lowercased().contains(query) || cask.token.lowercased().contains(query))
        }
        .sorted { lhs, rhs in
            if sortOrder == .mostDownloaded, lhs.downloadsIn365days != rhs.downloadsIn365days {
                return lhs.downloadsIn365days > rhs.downloadsIn365days
            }
            let comparison = lhs.name.localizedStandardCompare(rhs.name)
            if comparison != .orderedSame {
                return comparison == (sortOrder == .zToA ? .orderedDescending : .orderedAscending)
            }
            return lhs.fullToken < rhs.fullToken
        }
    }
}
