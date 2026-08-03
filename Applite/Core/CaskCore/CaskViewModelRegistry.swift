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

    /// Reconciles a boolean flag across every view model against `tokens` (short or full form).
    /// Only writes when the value actually changes — every assignment to an `@Observable`
    /// property fires `didSet`, so unconditional writes would re-render every dependent view.
    private func updateFlag(_ keyPath: ReferenceWritableKeyPath<CaskViewModel, Bool>, tokens: Set<CaskId>) {
        for vm in viewModelsByToken.values {
            let match = vm.matches(anyOf: tokens)
            if vm[keyPath: keyPath] != match {
                vm[keyPath: keyPath] = match
            }
        }
    }

    /// Marks casks as installed. Tokens can be short ("firefox") or full ("homebrew/cask/firefox").
    func markInstalled(tokens: Set<CaskId>) {
        updateFlag(\.isInstalled, tokens: tokens)
    }

    /// Marks casks as outdated. Tokens can be short or full.
    func markOutdated(tokens: Set<CaskId>) {
        updateFlag(\.isOutdated, tokens: tokens)
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

    /// O(n) counts that skip the O(n log n) `.sorted()` of the full list — for the always-on-screen
    /// sidebar badge, which only needs the number, not the ordered view models (D1).
    var installedCount: Int {
        viewModelsByToken.values.lazy.filter(\.isInstalled).count
    }

    var outdatedCount: Int {
        viewModelsByToken.values.lazy.filter(\.isOutdated).count
    }

    /// Total number of tracked view models
    var count: Int {
        viewModelsByToken.count
    }
}
