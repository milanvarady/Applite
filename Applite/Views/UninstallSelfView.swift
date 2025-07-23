//
//  UninstallSelfView.swift
//  Applite
//
//  Created by Milán Várady on 2023. 06. 14..
//

import SwiftUI

/// Uninstalls Applite and related files
struct UninstallSelfView: View {
    @State var deleteBrewCache = false
    @State var uninstallHomebrew = false
    @State var showConfirmation = false

    @StateObject var uninstallAlert = AlertManager()

    var body: some View {
        VStack(alignment: .leading) {
            Text("Uninstall Applite", comment: "Uninstall Applite window title")
                .font(.system(size: 26, weight: .bold))
                .padding(.bottom)
            
            Text("This will uninstall all files and cache associated with Applite.", comment: "Uninstall applite window description")

            Toggle("Delete Homebrew cache", isOn: $deleteBrewCache)
                .disabled(uninstallHomebrew)
            
            Text(
                "**Warning**: Homebrew cache is shared between Homebrew installations. Deleting the cache will remove the cache for all installations!",
                comment: "Uninstall Applite window cache warning"
            )
            
            Toggle("Uninstall Homebrew", isOn: $uninstallHomebrew)
                .onChange(of: uninstallHomebrew) { newValue in
                    if newValue {
                        deleteBrewCache = true
                    }
                }
            
            Text(
                "**Warning**: This will run the Homebrew uninstaller and remove Homebrew from all known locations and all packages installed. Administrator privileges may be required.",
                comment: "Uninstall Homebrew warning"
            )

            Divider()
                .padding(.vertical)
            
            Button(role: .destructive) {
                showConfirmation = true
            } label: {
                Label("Uninstall Applite", systemImage: "trash.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)

            Spacer()
        }
        .frame(width: 400, height: 320)
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

struct UninstallSelfView_Previews: PreviewProvider {
    static var previews: some View {
        UninstallSelfView()
    }
}
