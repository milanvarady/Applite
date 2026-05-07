//
//  CaskManager+LoadData.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.31.
//

import Foundation
import SwiftUI

extension CaskManager {
    /// Loads cask data in two stages:
    ///
    ///   1. Catalog (categories + taps) from the local DB — fast, no brew CLI dependency.
    ///      Commits to `categories`/`taps` as soon as it returns so the UI lights up.
    ///   2. Installed/outdated state from the brew CLI (slow). Updates the registry
    ///      reactively, so any view models already on screen flip their installed/outdated
    ///      flags without rebuilding the catalog views.
    func loadData() async throws {
        Self.logger.info("Starting data load process")

        // Stage 1: Catalog. Animate the placeholder→full transition so cask cards
        // cross-fade into place rather than swapping instantly mid-shimmer-cycle.
        let catalog = try await dataLoader.loadCatalogData()
        withAnimation(.easeInOut(duration: 0.25)) {
            self.categories = catalog.categories
            self.taps = catalog.taps
            self.isCatalogLoaded = true
        }

        // Stage 2: Brew CLI state
        self.isResolvingInstalledState = true
        defer { self.isResolvingInstalledState = false }

        async let installed: () = dataLoader.refreshInstalled()
        async let outdated: () = dataLoader.refreshOutdated()
        _ = try await (installed, outdated)

        Self.logger.info("Cask data loaded successfully!")
    }

    /// Refreshes the list of outdated casks
    func refreshOutdated() async throws {
        try await dataLoader.refreshOutdated()
    }
}
