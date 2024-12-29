//
//  Cask.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 04..
//

import SwiftUI
import os

/// A view model that holds all essential data of a Homebrew cask and provides methods to run brew commands on it (e.g. install, uninstall, update)
@MainActor
final class Cask: ObservableObject, Identifiable, Hashable {
    /// Static cask information
    let info: CaskInfo

    /// Number of downloads in the last 365 days
    let downloadsIn365days: Int

    // MARK: - Published properties

    @Published var isInstalled: Bool = false
    @Published var isOutdated: Bool = false

    /// Progress state of the cask when installing, updating or uninstalling
    @Published var progressState: ProgressState = .idle

    @Published var alert = AlertManager()

    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: Cask.self)
    )

    /// Cask progress state when installing, updating or uninstalling
    enum ProgressState: Equatable, Hashable {
        case idle
        case busy(withTask: String)
        case downloading(percent: Double)
        case success
        case failed(output: String)
    }

    required init(info: CaskInfo, downloadsIn365days: Int, isInstalled: Bool = false, isOutdated: Bool = false) {
        self.info = info
        self.downloadsIn365days = downloadsIn365days
        self.isInstalled = isInstalled
        self.isOutdated = isOutdated
    }

    static let dummy = Cask(info: CaskInfo(
        id: "test",
        name: "Test",
        description: "Test application",
        homepageURL: URL(string: "https://aerolite.dev/"),
        caveats: nil,
        pkgInstaller: false
    ), downloadsIn365days: 100)
}
