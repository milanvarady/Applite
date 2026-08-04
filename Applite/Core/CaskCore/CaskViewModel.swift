//
//  CaskViewModel.swift
//  Applite
//
//  Created by Milán Várady on 2026. 02. 11..
//

import SwiftUI
import OSLog

/// View model that combines static cask data from the database with runtime state
@Observable
@MainActor
final class CaskViewModel {
    /// Immutable identity token, used for nonisolated protocol conformances
    nonisolated private let _token: String
    /// Immutable identity full token, used for nonisolated protocol conformances
    nonisolated private let _fullToken: String

    /// Cask information from database
    private var record: CaskRecord

    // MARK: - Runtime State (not persisted)

    /// Whether the cask is currently installed
    var isInstalled: Bool = false

    /// Whether the cask has an update available
    var isOutdated: Bool = false

    /// Progress state when installing, updating, or uninstalling
    var progressState: CaskProgressState = .idle

    // MARK: - Initialization

    init(record: CaskRecord, isInstalled: Bool = false, isOutdated: Bool = false) {
        self._token = record.token
        self._fullToken = record.fullToken
        self.record = record
        self.isInstalled = isInstalled
        self.isOutdated = isOutdated
    }

    /// Updates the underlying record (e.g. after a database sync)
    func updateRecord(_ newRecord: CaskRecord) {
        self.record = newRecord
    }

    // MARK: - Computed Properties (forwarding from record)

    var token: String { record.token }
    var fullToken: String { record.fullToken }
    var tap: String { record.tap }
    var name: String { record.name }
    var descriptionText: String { record.descriptionText }
    var homepageURL: String? { record.homepageURL }
    var pkgInstaller: Bool { record.pkgInstaller }
    var downloadsIn365days: Int { record.downloadsIn365days }

    /// Homepage as URL
    var homepage: URL? { record.homepage }

    /// Warning information (deprecated, disabled, caveat)
    var warning: CaskWarning? { record.warning }

    /// True if this cask's short *or* full token is in `tokens`. Brew reports either form
    /// depending on the command, so membership checks must accept both.
    func matches(anyOf tokens: Set<CaskId>) -> Bool {
        tokens.contains(token) || tokens.contains(fullToken)
    }

    // MARK: - App Launch

    func launchApp() async throws {
        let token = self.token
        let displayName = self.name

        // Resolve the real bundle location off the main actor — a few stat calls plus a small
        // JSON read. `InstalledAppLocator` tries the Caskroom symlink, the cask's `app` artifact
        // name, a display-name guess, and finally a LaunchServices bundle-id lookup.
        let appURL = await Task.detached {
            InstalledAppLocator.appURL(token: token, displayName: displayName)
        }.value

        guard let appURL else {
            throw AppLaunchError.appNotFound(name: displayName)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    // MARK: - Dummy for Previews

    static let dummy = CaskViewModel(
        record: CaskRecord(
            token: "test",
            fullToken: "homebrew/cask/test",
            tap: "homebrew/cask",
            name: "Test",
            descriptionText: "Test application",
            homepageURL: "https://aerolite.dev/",
            pkgInstaller: false,
            warningType: nil,
            warningDate: nil,
            warningReason: nil,
            downloadsIn365days: 100
        ),
        isInstalled: false
    )
}

// MARK: - Icon URLs

extension CaskViewModel {
    /// Primary app-icon URL: CaskFlow's token-named icons (MIT), served via the jsDelivr CDN.
    /// jsDelivr avoids the unauthenticated `raw.githubusercontent.com` rate limits that a
    /// catalog full of icon loads would otherwise hit. Token characters (e.g. `+`) serve unencoded.
    ///
    /// Centralized here so every icon call site (app cards, the migration selection sheet) shares
    /// one source — the single edit point when the icon source is swapped.
    var iconURL: URL? {
        URL(string: "https://cdn.jsdelivr.net/gh/alielsokary/CaskFlow@icons/\(token).png")
    }

    /// Stable Kingfisher cache key for the icon. The `caskflow-` namespace deliberately differs
    /// from the bare token used by the previous (App-Fair) icon source, so existing installs
    /// re-fetch from CaskFlow instead of serving the old image cached under the plain token.
    var iconCacheKey: String { "caskflow-\(token)" }
}

// MARK: -  Protocol conformances

// MARK: - Identifiable
extension CaskViewModel: Identifiable {
    nonisolated var id: String {
        _fullToken
    }
}

// MARK: - Hashable
extension CaskViewModel: Hashable {
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Equatable
extension CaskViewModel: Equatable {
    nonisolated static func == (lhs: CaskViewModel, rhs: CaskViewModel) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Comparable
extension CaskViewModel: Comparable {
    nonisolated static func < (lhs: CaskViewModel, rhs: CaskViewModel) -> Bool {
        lhs._token < rhs._token
    }
}
