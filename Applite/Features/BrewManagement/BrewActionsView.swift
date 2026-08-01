//
//  BrewActionsView.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.01.
//

import SwiftUI
import ButtonKit

struct BrewActionsView: View {
    @Binding var modifyingBrew: Bool

    @Environment(CaskManager.self) private var caskManager

    @State var updateDone = false
    @State var reinstallDone = false

    @State var isAnnexBrewInstalled = false

    /// Whether Applite's own annex brew is the one currently selected. The refresh action only
    /// applies to the annex; a user's own brew is theirs to update.
    @State var isUsingAnnexBrew = false

    @State var isPresentingReinstallConfirm = false

    @State var updateFailed = false
    @State var reinstallFailed = false

    var body: some View {
        Group {
            if isUsingAnnexBrew {
                Section {
                    updateButton

                    remark(
                        title: "Note",
                        color: .blue,
                        message: "Re-fetches the latest Homebrew over Applite's installation. Your installed apps are kept."
                    )

                    remark(
                        title: "Warning",
                        color: .orange,
                        message: "All other app functions will be disabled during the refresh!"
                    )
                } header: {
                    Text("Refresh", comment: "Brew Management view refresh section title")
                }
            }

            Section {
                reinstallButton

                remark(
                    title: "Note",
                    color: .blue,
                    message: "This will (re)install Applite's Homebrew installation at: `~/Library/Application Support/Applite/Homebrew`"
                )

                remark(
                    title: "Warning",
                    color: .orange,
                    message: "After reinstalling, all currently installed apps will be unlinked from Applite. They won't be deleted, but you won't be able to update or uninstall them via Applite."
                )
            } header: {
                Text("Reinstall", comment: "Brew Management view reinstall section title")
            }
        }
        .task {
            // Check if brew is installed in application support
            isAnnexBrewInstalled = await BrewPaths.isBrewPathValid(at: BrewPaths.brewExecutable(for: .annex))
            isUsingAnnexBrew = BrewPaths.selectedBrewOption == .annex
        }
    }

    private func remark(title: LocalizedStringKey, color: Color, message: LocalizedStringKey) -> Text {
        Text(title)
            .foregroundStyle(color)
            .fontWeight(.bold)
        +
        Text(": ")
            .foregroundStyle(color)
            .fontWeight(.bold)
        +
        Text(message)
    }

    @MainActor
    private var updateButton: some View {
        HStack {
            AsyncButton {
                // Handle the failure inside the action rather than via `.onButtonStateError`,
                // which re-fires on every re-render while the button stays in its sticky error
                // state — so dismissing the alert would immediately re-present it in a loop.
                do {
                    try await refreshHomebrewComponents()
                } catch {
                    BrewManagementView.logger.error("Brew refresh failed. Error: \(error.localizedDescription)")
                    updateFailed = true
                }
            } label: {
                Label("Refresh Homebrew Components", systemImage: "arrow.clockwise.circle")
            }
            .controlSize(.large)
            .disabled(modifyingBrew)
            .alert("Refresh failed", isPresented: $updateFailed, actions: {})

            // Success checkmark
            if updateDone {
                Image(systemName: "checkmark.circle")
                    .imageScale(.large)
                    .foregroundStyle(.green)
            }
        }
    }

    @MainActor
    private var reinstallButton: some View {
        HStack {
            Button(role: .destructive) {
                isPresentingReinstallConfirm = true
            } label: {
                Label(isAnnexBrewInstalled ? "Reinstall Homebrew" : "Install Separate Brew", systemImage: "wrench.and.screwdriver")
            }
            .controlSize(.large)
            .disabled(modifyingBrew)
            .confirmationDialog("Are you sure you want to \(isAnnexBrewInstalled ? "re" : "")install Homebrew?", isPresented: $isPresentingReinstallConfirm) {
                AsyncButton("Reinstall", role: .destructive) {
                    withAnimation {
                        modifyingBrew = true
                    }

                    do {
                        try await AnnexBrewManager.installAnnexClean()
                    } catch {
                        reinstallFailed = true
                    }

                    if !reinstallFailed {
                        // A clean reinstall unlinks every previously-installed app, so the cached
                        // installed/outdated state is now stale — reload it so the UI reflects the
                        // unlinked apps instead of waiting for a manual ⌘R. Do this BEFORE showing
                        // the success tick, so the checkmark lands with the UI re-enable below
                        // rather than while the reload is still running.
                        await caskManager.loadData()
                        reinstallDone = true
                    }

                    withAnimation {
                        modifyingBrew = false
                    }
                }

                Button("Cancel", role: .cancel) { }
            } message: {
                if isAnnexBrewInstalled {
                    Text("All currently installed apps will be unlinked from Applite.", comment: "Brew reinstallation alert warning")
                } else {
                    Text("A new Homebrew installation will be installed into `~/Library/Application Support/Applite`", comment: "Brew installation alert notice")
                }
            }
            .alert("Reinstall failed", isPresented: $reinstallFailed, actions: {
                Button("OK", role: .cancel) { }
            })

            // Success checkmark
            if reinstallDone {
                Image(systemName: "checkmark.circle")
                    .imageScale(.large)
                    .foregroundStyle(.green)
            }
        }
    }

    func refreshHomebrewComponents() async throws {
        withAnimation {
            modifyingBrew = true
        }
        // Always clear the flag on exit — including a thrown refresh. Otherwise a failed refresh
        // (the AsyncButton surfaces the error separately) would leave every brew action disabled
        // until the app restarts.
        defer {
            withAnimation {
                modifyingBrew = false
            }
        }

        BrewManagementView.logger.info("Refreshing annex Homebrew started")

        // brew's git-based `brew update` can't run without Command Line Tools; re-fetch the tarball
        // over the annex instead (preserves installed apps).
        try await AnnexBrewManager.refreshAnnexBrew()

        BrewManagementView.logger.info("Annex Homebrew refresh successful")

        updateDone = true
    }
}
