//
//  Cask.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 04..
//

import SwiftUI
import os

/// Holds all essential data of a Homebrew cask and provides methods to run brew commands on it (e.g. install, uninstall, update)
@MainActor
final class Cask: Identifiable, Decodable, Hashable, ObservableObject {
    // MARK: - Static properties

    /// Unique id of the class, this is the same name you would use to download the cask with brew
    let id: String
    /// Longer format cask name
    let name: String
    /// Short description
    let description: String
    let homepageURL: URL?
    /// Number of downloads in the last 365 days
    var downloadsIn365days: Int = 0
    /// Description of any caveats with the app
    let caveats: String?
    /// If true app has a .pkg installer
    let pkgInstaller: Bool
    
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

    // MARK: - Initializers

    nonisolated init(from decoder: Decoder) throws {
        let rawData = try? CaskDTO(from: decoder)

        let homepage: String = rawData?.homepage ?? "https://brew.sh/"

        self.id = rawData?.token ?? "N/A"
        self.name = rawData?.nameArray[0] ?? "N/A"
        self.description = rawData?.desc ?? "N/A"
        self.homepageURL = URL(string: homepage)
        self.caveats = rawData?.caveats
        self.pkgInstaller = rawData?.url.hasSuffix("pkg") ?? false
    }
    
    init() {
        self.id = "test"
        self.name = "Test app"
        self.description = "An application to test this application"
        self.homepageURL = URL(string: "https://aerolite.dev/")
        self.caveats = nil
        self.pkgInstaller = false
    }
}
