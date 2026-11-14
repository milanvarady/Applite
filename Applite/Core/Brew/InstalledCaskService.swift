//
//  InstalledCaskService.swift
//  Applite
//
//  Created by Milán Várady on 2025.05.09.
//

import Foundation
import OSLog

/// Service for interacting with the brew CLI to manage installed casks
struct InstalledCaskService {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: InstalledCaskService.self)
    )

    /// Gets the list of installed casks
    /// - Returns: A set of Cask IDs representing installed casks
    func getInstalledCasks(configuration: BrewOperationConfiguration = .current) async throws -> Set<CaskId> {
        let output = try await Shell.run(configuration.executable, ["list", "--cask", "--full-name"])
        try configuration.validateCurrent()

        if output.isEmpty {
            logger.notice("No installed casks were found.")
        }

        let caskIds = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }

        return Set(caskIds)
    }

    /// Gets the list of outdated casks
    /// - Returns: A set of Cask IDs representing outdated casks
    func getOutdatedCasks(configuration: BrewOperationConfiguration = .current) async throws -> Set<CaskId> {
        var arguments: [String] = ["outdated", "--cask", "-q"]

        let greedy = UserDefaults.standard.value(for: Preferences.greedyUpgrade)

        if greedy {
            arguments.append("-g")
        }

        let output = try await Shell.run(configuration.executable, arguments)
        try configuration.validateCurrent()

        let caskIds = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .filter({ !$0.isEmpty })                                        // Remove empty strings
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })    // Trim whitespace

        return Set(caskIds)
    }
}
