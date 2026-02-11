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
    nonisolated let _token: String
    /// Immutable identity full token, used for nonisolated protocol conformances
    nonisolated let _fullToken: String

    /// Cask information from database
    private(set) var record: CaskRecord

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

    /// Whether this cask has any warning
    var hasWarning: Bool { record.hasWarning }

    // MARK: - Logger

    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: CaskViewModel.self)
    )

    // MARK: - App Launch

    func launchApp() async throws {
        let appPath: String

        if self.pkgInstaller {
            // Appdir
            if UserDefaults.standard.bool(forKey: Preferences.appdirOn.rawValue) {
                var applicationsDirectory = UserDefaults.standard.string(forKey: Preferences.appdirPath.rawValue) ?? URL.applicationDirectory.path

                // Remove trailing "/"
                if applicationsDirectory.hasSuffix("/") {
                    applicationsDirectory.removeLast()
                }
            }

            appPath = "\"\(URL.applicationDirectory.path)/\(self.name).app\""
        } else {
            // Open normal app
            let brewDirectory = BrewPaths.currentBrewDirectory.path(percentEncoded: false)

            appPath = "\(brewDirectory.replacingOccurrences(of: " ", with: "\\ "))/Caskroom/\(self.token)/*/*.app"
        }

        try await Shell.runAsync("open \(appPath)")
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
