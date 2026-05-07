//
//  CaskManager+LoadData.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.31.
//

import Foundation

extension CaskManager {
    /// Loads all cask data using the data loader
    func loadData() async throws {
        Self.logger.info("Starting data load process")

        let result = try await dataLoader.loadAllData()

        self.categories = result.categories
        self.taps = result.taps

        Self.logger.info("Cask data loaded successfully!")
    }

    /// Refreshes the list of outdated casks
    func refreshOutdated() async throws {
        try await dataLoader.refreshOutdated()
    }
}
