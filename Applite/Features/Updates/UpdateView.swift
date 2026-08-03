//
//  UpdateView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 14..
//

import SwiftUI
import ButtonKit

/// Update section
struct UpdateView: View {
    var casks: [CaskViewModel]

    @Environment(CaskManager.self) var caskManager

    @State var searchText = ""
    @State var isUpdatingAll = false
    @State var updateAllButtonRotation = 0.0

    @State var showingGreedyUpdateConfirm = false
    @State var loadAlert = AlertManager()

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
            AppGridView(casks: filteredCasks, appRole: .update)
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
                            do {
                                try await caskManager.refreshOutdated()
                            } catch {
                                loadAlert.show(title: "Failed to refresh updates", message: error.localizedDescription)
                            }
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
        .searchable(text: $searchText, placement: .toolbar)
        .toolbar {
            UpdateToolbar(loadAlert: loadAlert)
        }
        .alertManager(loadAlert)
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
}

#Preview {
    UpdateView(casks: Array(repeating: .dummy, count: 8))
        .frame(width: 500, height: 400)
}
