//
//  BrewManagementView+ActionsView.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.01.
//

import SwiftUI

extension BrewManagementView {
    struct ActionsView: View {
        @Binding var modifyingBrew: Bool
        let cardWidth: CGFloat
        let cardPadding: CGFloat
        let cardHeight: CGFloat = 210

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
                Text("Actions")
                    .font(.appliteSmallTitle)

                HStack {
                    ActionCard(
                        cardWidth: cardWidth,
                        cardHeight: cardHeight,
                        paddig: cardPadding,
                        actionSuccessful: $updateDone,
                        remarks: [
                            .init(title: "Warning", color: .orange, remark: "All other app functions will be disabled during the update!")
                        ]
                    ) {
                        updateButton
                    }

                    ActionCard(
                        cardWidth: cardWidth,
                        cardHeight: cardHeight,
                        paddig: cardPadding,
                        actionSuccessful: $reinstallDone,
                        remarks: [
                            .init(title: "Note", color: .blue, remark: "This will (re)install \(Bundle.main.appName)'s Homebrew installation at: ~/Library/Application Support/\(Bundle.main.appName)/homebrew"),
                            .init(title: "Warning", color: .orange, remark: "After reinstalling, all currently installed apps will be unlinked from \(Bundle.main.appName). They won't be deleted, but you won't be able to update or uninstall them via \(Bundle.main.appName).")
                        ]
                    ) {
                        reinstallButton
                    }
                }
                .padding(.bottom, 10)

                // Progress indicator
                if modifyingBrew {
                    HStack {
                        Text("In progress...")
                            .bold()
                        
                        SmallProgressView()
                    }
                }
            }
            .task {
                // Check if brew is installed in application support
                isAppBrewInstalled = await BrewPaths.isBrewPathValid(path: BrewPaths.getBrewExectuablePath(for: .appPath))
            }
        }

        private struct ActionCard<ActionButton: View>: View {
            let cardWidth: CGFloat
            let cardHeight: CGFloat
            let paddig: CGFloat
            @Binding var actionSuccessful: Bool
            let remarks: [Remark]
            @ViewBuilder let actionButton: ActionButton

            var body: some View {
                Card(cardWidth: cardWidth, cardHeight: cardHeight, paddig: paddig) {
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

                        Spacer()
                    }
                }
            }
        }

        @MainActor
        private var updateButton: some View {
            Button {
                withAnimation {
                    modifyingBrew = true
                }

                Task {
                    logger.info("Updating brew started")

                    do {
                        try await Shell.runBrewCommand(["update"])
                    } catch {
                        logger.error("Brew update failed. Error: \(error.localizedDescription)")
                        updateFailed = true
                    }

                    logger.info("Brew update successful")

                    updateDone = true

                    withAnimation {
                        modifyingBrew = false
                    }

                }
            } label: {
                Label("Update Homebrew", systemImage: "arrow.uturn.down.circle")
            }
            .controlSize(.large)
            .disabled(modifyingBrew)
            .padding(.trailing, 3)
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
                    Text("All currently installed apps will be unlinked from \(Bundle.main.appName).")
                } else {
                    Text("A new Homebrew installation will be installed into ~/Library/Application Support/\(Bundle.main.appName)")
                }
            }
            .alert("Reinstall failed", isPresented: $reinstallFailed, actions: {
                Button("OK", role: .cancel) { }
            })
        }
    }
}
