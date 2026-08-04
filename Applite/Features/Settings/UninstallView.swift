//
//  UninstallView.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

/// Uninstalls Applite and related files.
///
/// Used both as the Settings "Uninstall" tab and as the content of the
/// standalone `uninstall-self` window opened from the menu bar and the
/// Applite self-card.
struct UninstallView: View {
    @State private var deleteBrewCache = false
    @State private var uninstallHomebrew = false
    @State private var showConfirmation = false

    @State private var uninstallAlert = AlertManager()

    var body: some View {
        Form {
            Section {
                Text(
                    "This will uninstall Applite along with all files and cache associated with it.",
                    comment: "Uninstall applite description"
                )
            }

            Section {
                Toggle("Delete Homebrew cache", isOn: $deleteBrewCache)
                    .disabled(uninstallHomebrew)

                remark(
                    title: "Warning",
                    color: .orange,
                    message: "Homebrew cache is shared between Homebrew installations. Deleting the cache will remove the cache for all installations!"
                )

                Toggle("Uninstall Homebrew", isOn: $uninstallHomebrew)
                    .onChange(of: uninstallHomebrew) { _, newValue in
                        if newValue {
                            deleteBrewCache = true
                        }
                    }

                remark(
                    title: "Warning",
                    color: .orange,
                    message: "This will run the Homebrew uninstaller and remove Homebrew from all known locations along with every package installed. Administrator privileges may be required."
                )
            } header: {
                Label("Options", systemImage: "slider.horizontal.3")
            }

            Section {
                Button(role: .destructive) {
                    showConfirmation = true
                } label: {
                    Label("Uninstall Applite", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .controlSize(.large)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Are you sure you want to permanently uninstall Applite?", isPresented: $showConfirmation) {
            Button("Uninstall", role: .destructive) {
                Task.detached {
                    do {
                        try await uninstallSelf(deleteBrewCache: deleteBrewCache, uninstallHomebrew: uninstallHomebrew)
                    } catch {
                        await uninstallAlert.show(title: "Failed to uninstall", message: error.localizedDescription)
                    }
                }
            }

            Button("Cancel", role: .cancel) { }
        }
        .alertManager(uninstallAlert)
    }
}

#Preview {
    UninstallView()
}
