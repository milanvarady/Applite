//
//  UpdateView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 14..
//

import SwiftUI
import ButtonKit
import OSLog

/// Update section
struct UpdateView: View {
    var casks: [CaskViewModel]

    @Environment(CaskManager.self) var caskManager
    @AppStorage(Preferences.brewPathOption) private var brewPathOption
    @AppStorage(Preferences.customUserBrewPath) private var customUserBrewPath
    @AppStorage(Preferences.appdirOn) private var appdirOn
    @AppStorage(Preferences.appdirPath) private var appdirPath

    @State var searchText = ""
    @State private var versions: [String: UpdateVersionState] = [:]
    @State private var versionsKey: [String] = []
    @State private var versionsRetryCount = 0
    @State var isUpdatingAll = false
    @State var updateAllButtonRotation = 0.0

    @State var showingGreedyUpdateConfirm = false

    /// Filtered casks based on local search text
    var filteredCasks: [CaskViewModel] {
        if searchText.isEmpty {
            return casks
        }
        let query = searchText.lowercased()
        return casks.filter {
            $0.name.lowercased().contains(query) || $0.token.lowercased().contains(query)
        }
    }

    /// True while a bulk update is running. Reads the observable batch state (`batchProgress`),
    /// which survives leaving and re-entering this tab, OR the just-pressed local flag (which
    /// covers the brief gap before the batch actually starts). Deriving `disabled` from local
    /// `@State` alone was the bug: switching tabs destroys the view, resetting `isUpdatingAll`, so
    /// the button re-enabled mid-update.
    private var isUpdatingAllActive: Bool {
        isUpdatingAll || caskManager.batchProgress?.isUpdate == true
    }

    var updateAllButton: some View {
        Button {
            isUpdatingAll = true
            caskManager.updateAll(caskManager.outdatedViewModels)
        } label: {
            HStack {
                Image(systemName: "arrow.2.circlepath")
                    .rotationEffect(.degrees(updateAllButtonRotation))

                Text("Update All", comment: "Update all button title")
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.vertical)
        .disabled(isUpdatingAllActive)
    }

    /// Starts/stops the icon spin to track the running state — so it spins on press, resumes if you
    /// return to the tab mid-update, and stops when the batch ends.
    private func syncUpdateAllSpin(_ running: Bool) {
        if running {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                updateAllButtonRotation = 360.0
            }
        } else {
            withAnimation(.default) {
                updateAllButtonRotation = 0
            }
        }
    }

    var body: some View {
        VStack {
            // App grid
            AppGridView(casks: filteredCasks, appRole: .update,
                        updateVersions: versionsKey == versionKey ? versions : [:]) {
                versionsRetryCount += 1
            }
                .overlay(alignment: .bottom) {
                    if filteredCasks.count > 1 {
                        updateAllButton
                            .shadow(radius: 8)
                            .padding(.vertical)
                    }
                }
        }
        .overlay {
            if casks.isEmpty {
                if caskManager.outdatedRefreshFailed {
                    // The outdated check failed/never ran — don't claim everything is up to date.
                    ContentUnavailableView {
                        Label("Couldn't Check for Updates", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("Applite couldn't check which of your apps are outdated. Check your Homebrew installation and try again.", comment: "Update view outdated-check-failed description")
                    } actions: {
                        AsyncButton("Retry", systemImage: "arrow.clockwise") {
                            // No alert on failure: this empty state *is* the failure report, and a
                            // failed retry leaves it on screen saying so. `refreshOutdated` logs and
                            // keeps `outdatedRefreshFailed` set.
                            try? await caskManager.refreshOutdated()
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No Updates Available",
                        systemImage: "checkmark.circle",
                        description: Text("All your apps are up to date.", comment: "Update view no updates available description")
                    )
                }
            } else if filteredCasks.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .navigationTitle("Update")
        .task(id: versionKey) {
            await loadVersions()
        }
        .searchable(text: $searchText, placement: .toolbar)
        .toolbar {
            UpdateToolbar()
        }
        .onChange(of: isUpdatingAllActive) { _, running in
            syncUpdateAllSpin(running)
        }
        .onAppear {
            // Returning to the tab mid-update: resume the spin from the observable state.
            syncUpdateAllSpin(isUpdatingAllActive)
        }
        .onChange(of: caskManager.batchProgress) { old, new in
            // The bulk update finished (even if some casks failed and stay outdated) — clear the
            // local press flag so `isUpdatingAllActive` can fall back to false. Gate on the ended
            // batch being an update so a concurrent install-all ending doesn't reset us.
            if new == nil, old?.isUpdate == true {
                isUpdatingAll = false
            }
        }
    }

    private var versionKey: [String] {
        [String(brewPathOption), customUserBrewPath, String(appdirOn), appdirPath,
         String(caskManager.successfulCatalogRefreshRevision), String(versionsRetryCount)] +
        casks.flatMap {
            [$0.cardIdentity, String($0.isInstalled), $0.selectedInstallationURL?.path ?? "",
             String($0.displayedProtection != nil), String($0.metadataRevision)]
        }
    }

    private func loadVersions() async {
        let key = versionKey
        let candidates = casks
        guard !Task.isCancelled, key == versionKey else { return }
        versionsKey = key
        versions = Dictionary(candidates.map { ($0.cardIdentity, .loading) }, uniquingKeysWith: { first, _ in first })
        let configuration = BrewOperationConfiguration.current
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Applite", category: "UpdateVersions")
        for cask in candidates {
            guard !Task.isCancelled, key == versionKey else { return }
            let identity = cask.cardIdentity
            let token = cask.token
            let name = cask.name
            let url = cask.selectedInstallationURL
            let isManaged = cask.isInstalled
            let hasOtherOwner = cask.displayedProtection != nil
            var errors: [String] = []
            let metadata: InstalledAppMetadata?
            do {
                metadata = try await Task.detached {
                    guard let path = try InstalledAppLocator.metadataAppURL(
                        token: token, displayName: name, preferredURL: url,
                        isManaged: isManaged, configuration: configuration
                    ) else { return nil }
                    return try InstalledAppMetadata.read(at: path)
                }.value
            } catch {
                guard !Task.isCancelled, key == versionKey else { return }
                logger.error("Could not read installed version for \(cask.fullToken, privacy: .public): \(error.localizedDescription)")
                errors.append(String(localized: "Installed app information: \(error.localizedDescription)"))
                metadata = nil
            }
            guard !Task.isCancelled, key == versionKey else { return }
            let info: CaskAdditionalInfo?
            do {
                info = try await caskManager.getAdditionalInfoForCask(cask)
            } catch {
                guard !Task.isCancelled, key == versionKey else { return }
                logger.error("Could not load Homebrew version for \(cask.fullToken, privacy: .public): \(error.localizedDescription)")
                errors.append(String(localized: "Homebrew information: \(error.localizedDescription)"))
                info = nil
            }
            guard !Task.isCancelled, key == versionKey else { return }
            let resolved = UpdateVersions.resolve(
                isLocallyInstalled: cask.isLocallyInstalled, isHomebrewManaged: isManaged,
                hasOtherOwner: hasOtherOwner, metadata: metadata, brew: info
            )
            versions[identity] = .loaded(resolved, error: errors.isEmpty ? nil : errors.joined(separator: "\n"))
        }
    }
}

#Preview {
    UpdateView(casks: Array(repeating: .dummy, count: 8))
        .frame(width: 500, height: 400)
}
