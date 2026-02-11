//
//  CaskViewModelRegistry.swift
//  Applite
//
//  Created by Milán Várady on 2026. 02. 11..
//

import Foundation
import OSLog

/// Central registry that owns all live CaskViewModel instances, keyed by token.
/// Ensures the same cask appearing in multiple contexts (category, installed list, search)
/// shares a single view model so progress/state changes are visible everywhere.
@Observable
@MainActor
final class CaskViewModelRegistry {
    /// All live view models keyed by cask token
    private var viewModelsByToken: [String: CaskViewModel] = [:]

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: CaskViewModelRegistry.self)
    )

    // MARK: - Lookup & Creation

    /// Returns an existing view model for the token, or creates a new one from the record
    func viewModel(for record: CaskRecord) -> CaskViewModel {
        if let existing = viewModelsByToken[record.token] {
            existing.updateRecord(record)
            return existing
        }
        let vm = CaskViewModel(record: record)
        viewModelsByToken[record.token] = vm
        return vm
    }

    /// Batch version: returns view models for multiple records, reusing existing instances
    func viewModels(for records: [CaskRecord]) -> [CaskViewModel] {
        records.map { viewModel(for: $0) }
    }

    /// Looks up an existing view model by token without creating one
    func existingViewModel(forToken token: String) -> CaskViewModel? {
        viewModelsByToken[token]
    }

    // MARK: - Bulk State Updates

    /// Marks casks as installed. Tokens can be short ("firefox") or full ("homebrew/cask/firefox").
    func markInstalled(tokens: Set<String>) {
        for (key, vm) in viewModelsByToken {
            let match = tokens.contains(key) || tokens.contains(vm.fullToken)
            vm.isInstalled = match
        }
    }

    /// Marks casks as outdated. Tokens can be short or full.
    func markOutdated(tokens: Set<String>) {
        for (key, vm) in viewModelsByToken {
            let match = tokens.contains(key) || tokens.contains(vm.fullToken)
            vm.isOutdated = match
        }
    }

    // MARK: - Computed Filtered Lists

    /// All currently installed view models, sorted by name
    var installedViewModels: [CaskViewModel] {
        viewModelsByToken.values
            .filter(\.isInstalled)
            .sorted()
    }

    /// All currently outdated view models, sorted by name
    var outdatedViewModels: [CaskViewModel] {
        viewModelsByToken.values
            .filter(\.isOutdated)
            .sorted()
    }

    // MARK: - Memory Management

    /// Removes view models that are no longer needed, keeping installed, outdated, and in-progress VMs.
    /// Call after loading to free memory from VMs that were only needed transiently.
    func pruneUnused(keepTokens: Set<String>) {
        let toRemove = viewModelsByToken.filter { key, vm in
            !keepTokens.contains(key)
            && !vm.isInstalled
            && !vm.isOutdated
            && vm.progressState == .idle
        }

        for key in toRemove.keys {
            viewModelsByToken.removeValue(forKey: key)
        }

        if !toRemove.isEmpty {
            logger.debug("Pruned \(toRemove.count) unused view models")
        }
    }

    /// Total number of tracked view models
    var count: Int {
        viewModelsByToken.count
    }
}
