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
    private var viewModelsByToken: [CaskId: CaskViewModel] = [:]

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
    func existingViewModel(forToken token: CaskId) -> CaskViewModel? {
        viewModelsByToken[token]
    }
    
    /// Looks up an existing view models by token without creating them
    func existingViewModels(forTokens tokens: Set<CaskId>) -> [CaskViewModel] {
        return tokens.compactMap {
            viewModelsByToken[$0]
        }
    }

    // MARK: - Bulk State Updates

    /// Marks casks as installed. Tokens can be short ("firefox") or full ("homebrew/cask/firefox").
    /// Only writes when the value actually changes — every assignment to an `@Observable`
    /// property fires `didSet`, so unconditional writes would re-render every dependent view.
    func markInstalled(tokens: Set<CaskId>) {
        for (key, vm) in viewModelsByToken {
            let match = tokens.contains(key) || tokens.contains(vm.fullToken)
            if vm.isInstalled != match {
                vm.isInstalled = match
            }
        }
    }

    /// Marks casks as outdated. Tokens can be short or full.
    func markOutdated(tokens: Set<CaskId>) {
        for (key, vm) in viewModelsByToken {
            let match = tokens.contains(key) || tokens.contains(vm.fullToken)
            if vm.isOutdated != match {
                vm.isOutdated = match
            }
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

    /// All view models currently performing an operation (install, update, uninstall)
    var busyViewModels: [CaskViewModel] {
        viewModelsByToken.values.filter { $0.progressState != .idle }
    }

    /// Total number of tracked view models
    var count: Int {
        viewModelsByToken.count
    }
}
