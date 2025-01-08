//
//  AppView+OpenAndManageView.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension AppView {
    /// Button used in the Download section, launches, uninstalls or reinstalls the app
    struct OpenAndManageView: View {
        @ObservedObject var cask: Cask
        let deleteButton: Bool

        @EnvironmentObject var caskManager: CaskManager

        @State var showAppNotFoundAlert = false
        @State var showPopover = false

        @State private var isOptionKeyDown = false

        var body: some View {
            // Lauch app
            Button("Open") {
                Task {
                    do {
                        try await cask.launchApp()
                    } catch {
                        showAppNotFoundAlert = true
                    }
                }
            }
            .font(.system(size: 14))
            .buttonStyle(.bordered)
            .clipShape(Capsule())
            .alert("Applite couldn't open \(cask.info.name)", isPresented: $showAppNotFoundAlert) {}

            if deleteButton {
                UninstallButton(cask: cask)
            }

            // More options popover
            Button() {
                showPopover = true
            } label: {
                Image(systemName: "chevron.down")
                    .padding(.vertical)
                    .contentShape(Rectangle())
            }
            .popover(isPresented: $showPopover) {
                VStack(alignment: .leading, spacing: 6) {
                    GetInfoButton(cask: cask)
                    
                    // Reinstall button
                    Button {
                        caskManager.reinstall(cask)
                    } label: {
                        Label("Reinstall", systemImage: "arrow.2.squarepath")
                    }

                    // Uninstall button
                    Button(role: .destructive) {
                        Task {
                            caskManager.uninstall(cask)
                        }
                    } label: {
                        Label("Uninstall", systemImage: "trash")
                            .foregroundStyle(.red)
                    }

                    // Uninstall completely button
                    Button(role: .destructive) {
                        Task {
                            caskManager.uninstall(cask, zap: true)
                        }
                    } label: {
                        Label("Uninstall Completely", systemImage: "trash.fill")
                            .foregroundStyle(.red)
                    }
                }
                .padding(8)
                .buttonStyle(.plain)
            }
        }
    }
}
