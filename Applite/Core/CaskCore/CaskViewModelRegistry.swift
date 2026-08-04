//
//  CaskViewModelRegistry.swift
//  Applite
//
//  Created by Milán Várady on 2026. 02. 11..
//

import Foundation
import OSLog

/// Central registry that owns all live CaskViewModel instances, keyed by full token.
/// Ensures the same cask appearing in multiple contexts (category, installed list, search)
/// shares a single view model so progress/state changes are visible everywhere.
///
/// Keyed by `fullToken`, not the bare token, for the same reason the `casks` table is: two taps can
/// each ship a "firefox", and keying on the bare token silently made them one view model — the
/// second record to arrive would overwrite the first's record and both cards would show it.
@Observable
@MainActor
final class CaskViewModelRegistry {
    /// All live view models keyed by cask full token
    private var viewModelsByFullToken: [CaskId: CaskViewModel] = [:]

    // MARK: - Lookup & Creation

    /// Returns an existing view model for the record, or creates a new one
    func viewModel(for record: CaskRecord) -> CaskViewModel {
        if let existing = viewModelsByFullToken[record.fullToken] {
            existing.updateRecord(record)
            return existing
        }
        let vm = CaskViewModel(record: record)
        viewModelsByFullToken[record.fullToken] = vm
        return vm
    }

    /// Batch version: returns view models for multiple records, reusing existing instances
    func viewModels(for records: [CaskRecord]) -> [CaskViewModel] {
        records.map { viewModel(for: $0) }
    }

    // MARK: - Bulk State Updates

    /// Reconciles a boolean flag across every view model using `isMatch`.
    /// Only writes when the value actually changes — every assignment to an `@Observable`
    /// property fires `didSet`, so unconditional writes would re-render every dependent view.
    private func updateFlag(
        _ keyPath: ReferenceWritableKeyPath<CaskViewModel, Bool>,
        isMatch: (CaskViewModel) -> Bool
    ) {
        for vm in viewModelsByFullToken.values {
            let match = isMatch(vm)
            if vm[keyPath: keyPath] != match {
                vm[keyPath: keyPath] = match
            }
        }
    }

    /// Marks casks as installed from `brew list --cask --full-name`, which prints each cask's
    /// `full_name` — so this is an exact `fullToken` match.
    func markInstalled(tokens: Set<CaskId>) {
        updateFlag(\.isInstalled) { $0.matchesFullName(in: tokens) }
    }

    /// Marks casks as outdated from `brew outdated --cask -q`, which prints **bare** tokens even for
    /// tap casks. That's ambiguous across taps, so it's gated on `isInstalled`: only one of two
    /// same-token casks can be the installed one, and installed state is reconciled first (see
    /// `CaskManager.loadInstalledState`, which awaits `refreshInstalled` before `refreshOutdated`).
    func markOutdated(tokens: Set<CaskId>) {
        updateFlag(\.isOutdated) { $0.isInstalled && $0.matchesBareToken(in: tokens) }
    }

    // MARK: - Computed Filtered Lists

    /// All currently installed view models, sorted by name
    var installedViewModels: [CaskViewModel] {
        viewModelsByFullToken.values
            .filter(\.isInstalled)
            .sorted()
    }

    /// All currently outdated view models, sorted by name
    var outdatedViewModels: [CaskViewModel] {
        viewModelsByFullToken.values
            .filter(\.isOutdated)
            .sorted()
    }

    /// O(n) counts that skip the O(n log n) `.sorted()` of the full list — for the always-on-screen
    /// sidebar badge, which only needs the number, not the ordered view models (D1).
    var installedCount: Int {
        viewModelsByFullToken.values.lazy.filter(\.isInstalled).count
    }

    var outdatedCount: Int {
        viewModelsByFullToken.values.lazy.filter(\.isOutdated).count
    }

    /// Total number of tracked view models
    var count: Int {
        viewModelsByFullToken.count
    }
}
