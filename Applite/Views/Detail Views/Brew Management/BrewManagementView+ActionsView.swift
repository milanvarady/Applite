//
//  BrewManagementView+ActionsView.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.01.
//

import SwiftUI
import ButtonKit

extension BrewManagementView {
    struct ActionsView: View {
        @Binding var modifyingBrew: Bool
        let cardWidth: CGFloat
        let cardPadding: CGFloat

        @State var updateDone = false
        @State var reinstallDone = false

        @State var isAppBrewInstalled = false

        @State var isPresentingReinstallConfirm = false

        @State var updateFailed = false
        @State var reinstallFailed = false

        private struct Remark: Identifiable {
            let title: LocalizedStringKey
            let color: Color
            let remark: LocalizedStringKey

            var id = UUID()
        }

        var body: some View {
            VStack(alignment: .leading) {
                Text("Actions", comment: "Brew Management view action section title")
                    .font(.appliteSmallTitle)

                HStack {
                    ActionCard(
                        paddig: cardPadding,
                        actionSuccessful: $updateDone,
                        remarks: [
                            .init(title: "Warning", color: .orange, remark: "All other app functions will be disabled during the update!")
                        ]
                    ) {
                        updateButton
                    }
                    .frame(width: cardWidth)

                    ActionCard(
                        paddig: cardPadding,
                        actionSuccessful: $reinstallDone,
                        remarks: [
                            .init(title: "Note", color: .blue, remark: "This will (re)install Applite's Homebrew installation at: `~/Library/Application Support/Applite/homebrew`"),
                            .init(title: "Warning", color: .orange, remark: "After reinstalling, all currently installed apps will be unlinked from Applite. They won't be deleted, but you won't be able to update or uninstall them via Applite.")
                        ]
                    ) {
                        reinstallButton
                    }
                    .frame(width: cardWidth)
                }
                .padding(.bottom, 10)

                // Progress indicator
                if modifyingBrew {
                    HStack {
                        Text("In progress...", comment: "Brew Management view progress indicator")
                            .bold()
                        
                        SmallProgressView()
                    }
                }
            }
            .task {
                // Check if brew is installed in application support
                isAppBrewInstalled = await BrewPaths.isBrewPathValid(at: BrewPaths.getBrewExectuablePath(for: .appPath))
            }
        }

        private struct ActionCard<ActionButton: View>: View {
            let paddig: CGFloat
            @Binding var actionSuccessful: Bool
            let remarks: [Remark]
            @ViewBuilder let actionButton: ActionButton

            var body: some View {
                Card(paddig: paddig) {
                    VStack(alignment: .leading) {
                        HStack {
                            actionButton

                            // Success checkmark
                            if actionSuccessful {
                                Image(systemName: "checkmark.circle")
                                    .imageScale(.large)
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(.bottom, 12)

                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(remarks) { remark in
                                Text(remark.title)
                                    .foregroundColor(remark.color)
                                    .fontWeight(.bold)
                                +
                                Text(": ")
                                    .foregroundColor(remark.color)
                                    .fontWeight(.bold)
                                +
                                Text(remark.remark)
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .topLeading) // Don't trucate text

                        Spacer()
                    }
                }
            }
        }

        @MainActor
        private var updateButton: some View {
            AsyncButton {
                try await updateHomebrew()
            } label: {
                Label("Update Homebrew", systemImage: "arrow.uturn.down.circle")
            }
            .controlSize(.large)
            .disabled(modifyingBrew)
            .padding(.trailing, 3)
            .onButtonError { error in
                logger.error("Brew update failed. Error: \(error.localizedDescription)")
                updateFailed = true
            }
            .alert("Update failed", isPresented: $updateFailed, actions: {})
        }

        @MainActor
        private var reinstallButton: some View {
            Button(role: .destructive) {
                isPresentingReinstallConfirm = true
            } label: {
                Label(isAppBrewInstalled ? "Reinstall Homebrew" : "Install Separate Brew", systemImage: "wrench.and.screwdriver")
            }
            .controlSize(.large)
            .disabled(modifyingBrew)
            .confirmationDialog("Are you sure you want to \(isAppBrewInstalled ? "re" : "")install Homebrew?", isPresented: $isPresentingReinstallConfirm) {
                Button("Reinstall", role: .destructive) {
                    withAnimation {
                        modifyingBrew = true
                    }

                    Task {
                        do {
                            try await DependencyManager.installHomebrew()
                        } catch {
                            reinstallFailed = true
                        }

                        if !reinstallFailed {
                            reinstallDone = true
                        }

                        withAnimation {
                            modifyingBrew = false
                        }
                    }
                }

                Button("Cancel", role: .cancel) { }
            } message: {
                if isAppBrewInstalled {
                    Text("All currently installed apps will be unlinked from Applite.", comment: "Brew reinstallation alert warning")
                } else {
                    Text("A new Homebrew installation will be installed into `~/Library/Application Support/Applite`", comment: "Brew installation alert notice")
                }
            }
            .alert("Reinstall failed", isPresented: $reinstallFailed, actions: {
                Button("OK", role: .cancel) { }
            })
        }

        func updateHomebrew() async throws {
            withAnimation {
                modifyingBrew = true
            }

            logger.info("Updating brew started")

            try await Shell.runBrewCommand(["update"])

            logger.info("Brew update successful")

            updateDone = true

            withAnimation {
                modifyingBrew = false
            }
        }
    }
}
