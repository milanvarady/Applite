//
//  CaskManager+RefreshOutdated.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.31.
//

import Foundation

extension CaskManager {
    func refreshOutdated(greedy: Bool = false) async throws -> Void {
        var arguments: [String] = ["outdated", "--cask", "-q"]

        if greedy {
            arguments.append("-g")
        }

        let output = try await Shell.runBrewCommand(arguments)

        let outdatedCaskIDs = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .filter({ !$0.isEmpty })                                        // Remove empty strings
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })    // Trim whitespace

        self.outdatedCasks.removeAll()

        var outdatedCasks: [Cask] = []

        for caskID in outdatedCaskIDs {
            if let cask = self.casks[caskID] {
                // Check if cask is installed because sometimes random casks appear
                // in the outdated section for reasons beyond my comprehension
                if cask.isInstalled {
                    outdatedCasks.append(cask)
                }
            }
        }

        self.outdatedCasks.defineCasks(outdatedCasks)

        Self.logger.info("Outdated apps refreshed")
    }
}
