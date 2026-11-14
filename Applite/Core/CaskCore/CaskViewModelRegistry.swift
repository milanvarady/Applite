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
    private var additionalCopies: [String: CaskViewModel] = [:]
    private var outdatedTokens: Set<CaskId> = []

    // MARK: - Lookup & Creation

    /// Returns an existing view model for the record, or creates a new one
    func viewModel(for record: CaskRecord) -> CaskViewModel {
        if let existing = viewModelsByFullToken[record.fullToken] {
            existing.updateRecord(record)
            for copy in additionalCopies.values where copy.fullToken == record.fullToken {
                copy.updateRecord(record)
            }
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

    func materializeMissingViewModels(for records: [CaskRecord]) {
        for record in records where viewModelsByFullToken[record.fullToken] == nil {
            _ = viewModel(for: record)
        }
    }

    func updateExistingViewModels(for records: [CaskRecord]) {
        for record in records where viewModelsByFullToken[record.fullToken] != nil {
            _ = viewModel(for: record)
        }
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

    func markExternalInstallations(
        appURLs: [CaskId: URL], appStoreAppURLs: [CaskId: URL] = [:],
        intuneAppURLs: [CaskId: URL] = [:], setappAppURLs: [CaskId: URL] = [:],
        artCraftAppURLs: [CaskId: URL] = [:], bundleURLs: [CaskId: URL]? = nil,
        copies: [CaskId: [ExternalAppDetector.AdditionalInstallation]] = [:],
        multipleCopyTokens: Set<CaskId> = [],
        selectedCopyProtection: [CaskId: ProtectedAppInstallation] = [:]
    ) {
        applyManagementSourceOverrides()
        for vm in viewModelsByFullToken.values {
            vm.hasMultipleInstalledCopies = multipleCopyTokens.contains(vm.fullToken)
            vm.hasSelectedCopyProvenance = vm.hasMultipleInstalledCopies
            vm.selectedCopyProtection = selectedCopyProtection[vm.fullToken]
            let urls: [ProtectedAppInstallation.Source: URL?] = [
                .intune: intuneAppURLs[vm.fullToken], .appStore: appStoreAppURLs[vm.fullToken],
                .setapp: setappAppURLs[vm.fullToken], .artCraft: artCraftAppURLs[vm.fullToken]
            ]
            let protection = ProtectedAppInstallation(appURLs: urls.compactMapValues { $0 })
            if let bundleURLs {
                vm.installedBundleURL = bundleURLs[vm.fullToken]
            } else if let url = appURLs[vm.fullToken] {
                vm.installedBundleURL = url.standardizedFileURL
            }
            if vm.protectedAppInstallation != protection {
                vm.protectedAppInstallation = protection
            }
            if vm.isManagementProtected { vm.isOutdated = false }
            let url = vm.isInstalled ? nil : appURLs[vm.fullToken]
            if vm.externalAppURL != url {
                vm.externalAppURL = url
            }
        }
        var currentCopies: [String: CaskViewModel] = [:]
        for (token, installations) in copies {
            guard let primary = viewModelsByFullToken[token] else { continue }
            for installation in installations {
                let newCopy = primary.installedCopy(at: installation.url)
                let copy = additionalCopies[newCopy.id] ?? newCopy
                copy.externalAppURL = installation.url
                copy.installedBundleURL = installation.url
                copy.protectedAppInstallation = installation.protection
                copy.managementSourceOverrides = ProtectedAppInstallation.Source.enabledOverrides()
                copy.hasMultipleInstalledCopies = true
                currentCopies[copy.id] = copy
            }
        }
        for (id, copy) in additionalCopies where currentCopies[id] == nil {
            copy.externalAppURL = nil
            copy.installedBundleURL = nil
            copy.protectedAppInstallation = nil
        }
        additionalCopies = currentCopies
    }

    func updateManagedBundleURLs(
        _ urls: [CaskId: URL], multipleCopyTokens: Set<CaskId>,
        selectedCopyProtection: [CaskId: ProtectedAppInstallation]
    ) {
        for vm in viewModelsByFullToken.values where vm.isInstalled {
            let url = urls[vm.fullToken]
            if vm.installedBundleURL == url && !multipleCopyTokens.contains(vm.fullToken) {
                continue
            }
            vm.installedBundleURL = url
            vm.hasSelectedCopyProvenance = multipleCopyTokens.contains(vm.fullToken)
            vm.selectedCopyProtection = selectedCopyProtection[vm.fullToken]
            if let selected = vm.selectedCopyProtection {
                var sources = vm.protectedAppInstallation?.appURLs ?? [:]
                sources.merge(selected.appURLs) { _, current in current }
                vm.protectedAppInstallation = ProtectedAppInstallation(appURLs: sources)
                if vm.isManagementProtected { vm.isOutdated = false }
            }
        }
    }

    @discardableResult
    func applyManagementSourceOverrides() -> Bool {
        let overrides = ProtectedAppInstallation.Source.enabledOverrides()
        var changed = false
        for vm in viewModelsByFullToken.values {
            if vm.managementSourceOverrides != overrides {
                vm.managementSourceOverrides = overrides
                changed = true
            }
            if vm.isManagementProtected && vm.isOutdated { vm.isOutdated = false }
        }
        for vm in additionalCopies.values {
            if vm.managementSourceOverrides != overrides {
                vm.managementSourceOverrides = overrides
                changed = true
            }
        }
        return changed
    }

    func clearExternalInstallations() {
        applyManagementSourceOverrides()
        for vm in viewModelsByFullToken.values where vm.externalAppURL != nil {
            vm.externalAppURL = nil
        }
        for vm in viewModelsByFullToken.values {
            vm.hasMultipleInstalledCopies = false
            if !vm.isInstalled {
                vm.hasSelectedCopyProvenance = false
                vm.selectedCopyProtection = nil
            }
        }
        for copy in additionalCopies.values {
            copy.externalAppURL = nil
            copy.installedBundleURL = nil
            copy.protectedAppInstallation = nil
        }
        additionalCopies.removeAll()
    }

    func clearHomebrewManagementErrors() {
        for vm in viewModelsByFullToken.values where vm.homebrewManagementError != nil {
            vm.homebrewManagementError = nil
        }
    }

    /// Marks casks as outdated from `brew outdated --cask -q`, which prints **bare** tokens even for
    /// tap casks. That's ambiguous across taps, so it's gated on `isInstalled`: only one of two
    /// same-token casks can be the installed one, and installed state is reconciled first (see
    /// `CaskManager.loadInstalledState`, which awaits `refreshInstalled` before `refreshOutdated`).
    func markOutdated(tokens: Set<CaskId>) {
        outdatedTokens = tokens
        updateFlag(\.isOutdated) {
            $0.isInstalled && !$0.isManagementProtected
                && $0.homebrewManagementBlockReason == nil && $0.matchesBareToken(in: tokens)
        }
    }

    // MARK: - Computed Filtered Lists

    private var locallyInstalledProjection: [CaskViewModel] {
        var byBundle: [String: CaskViewModel] = [:]
        for vm in Array(viewModelsByFullToken.values) + Array(additionalCopies.values)
            where vm.isLocallyInstalled && !vm.isApplite {
            let url = vm.installedBundleURL ?? vm.externalAppURL ?? vm.protectedAppInstallation?.url
            let identity = url.map { "bundle:\($0.standardizedFileURL.path)" } ?? "cask:\(vm.fullToken)"
            if let existing = byBundle[identity] {
                if vm.isInstalled != existing.isInstalled {
                    if vm.isInstalled { byBundle[identity] = vm }
                } else if vm.fullToken < existing.fullToken {
                    byBundle[identity] = vm
                }
            } else {
                byBundle[identity] = vm
            }
        }
        return Array(byBundle.values)
    }

    var locallyInstalledViewModels: [CaskViewModel] {
        locallyInstalledProjection.sorted()
    }

    var locallyInstalledCount: Int {
        locallyInstalledProjection.count
    }

    /// All currently installed view models, sorted by name
    var installedViewModels: [CaskViewModel] {
        viewModelsByFullToken.values
            .filter(\.isInstalled)
            .sorted()
    }

    /// All currently outdated view models, sorted by name
    var outdatedViewModels: [CaskViewModel] {
        viewModelsByFullToken.values
            .filter { $0.isOutdated && !$0.isManagementProtected && $0.homebrewManagementBlockReason == nil }
            .sorted()
    }

    var externalInstalledViewModels: [CaskViewModel] {
        (Array(viewModelsByFullToken.values) + Array(additionalCopies.values))
            .filter(\.isInstalledExternally).sorted()
    }

    var externalInstalledCount: Int {
        viewModelsByFullToken.values.lazy.filter(\.isInstalledExternally).count
            + additionalCopies.values.lazy.filter(\.isInstalledExternally).count
    }

    /// O(n) counts that skip the O(n log n) `.sorted()` of the full list — for the always-on-screen
    /// sidebar badge, which only needs the number, not the ordered view models (D1).
    var installedCount: Int {
        viewModelsByFullToken.values.lazy.filter(\.isInstalled).count
    }

    var outdatedCount: Int {
        viewModelsByFullToken.values.lazy.filter {
            $0.isOutdated && !$0.isManagementProtected && $0.homebrewManagementBlockReason == nil
        }.count
    }

    var hasNonActionableOutdated: Bool {
        let actionable = Set(outdatedViewModels.map(\.token))
        return !outdatedTokens.subtracting(actionable).isEmpty
    }

    /// Total number of tracked view models
    var count: Int {
        viewModelsByFullToken.count
    }
}
