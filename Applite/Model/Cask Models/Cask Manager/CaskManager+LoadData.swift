//
//  CaskManager+LoadData.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.31.
//

import Foundation
import SwiftUI

extension CaskManager {
    /// Loads all cask data using the coordinator
    func loadData() async throws {
        Self.logger.info("Starting data load process")

        // Load data through coordinator
        let result = try await dataCoordinator.loadAllCaskData()

        // Update the manager with the results
        self.casks = result.allCasks
        self.allCasks.defineCasks(result.allCasksCollection.casks)
        self.installedCasks.defineCasks(result.installedCasksCollection.casks)
        self.outdatedCasks.defineCasks(result.outdatedCasksCollection.casks)
        self.categories = result.categories
        self.taps = result.taps

        Self.logger.info("Cask data loaded successfully!")
    }

    /// Refreshes the list of outdated casks
    func refreshOutdated() async throws -> Void {
        let outdatedCaskIds = try await dataCoordinator.getOutdatedCasks()

        self.outdatedCasks.removeAll()

        var outdatedCasks: [Cask] = []

        for caskID in outdatedCaskIds {
            if let cask = self.casks[caskID] {
                // Check if cask is installed because sometimes random casks appear
                // in the outdated section for reasons beyond my comprehension
                if cask.isInstalled {
                    outdatedCasks.append(cask)
                }
            }
        }

        self.outdatedCasks.defineCasks(outdatedCasks.sorted())

        Self.logger.info("Outdated casks refreshed successfully")
    }
}
