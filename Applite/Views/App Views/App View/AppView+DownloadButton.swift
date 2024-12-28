//
//  AppView+DownloadButton.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension AppView {
    /// Button used in the Download section, downloads the app
    struct DownloadButton: View {
        @ObservedObject var cask: Cask

        @EnvironmentObject var caskData: CaskData

        // Alerts
        @State var showingPopover = false
        @State var showingCaveats = false
        @State var showingBrewError = false
        @State var showingForceInstallConfirmation = false

        @State var buttonFill = false

        var body: some View {
            /// Download button
            Button {
                if cask.caveats != nil {
                    // Show caveats dialog
                    showingCaveats = true
                    return
                }

                download()
            } label: {
                Image(systemName: "arrow.down.to.line.circle\(buttonFill ? ".fill" : "")")
                    .font(.system(size: 22))
                    .foregroundColor(.accentColor)
            }
            .padding(.trailing, -8)
            .onHover { isHovering in
                // Hover effect
                withAnimation(.snappy) {
                    buttonFill = isHovering
                }
            }
            .alert("App caveats", isPresented: $showingCaveats) {
                Button("Download Anyway") {
                    download()
                }

                Button("Cancel", role: .cancel) { }
            } message: {
                Text(cask.caveats ?? "")
            }
            .alert("Broken Brew Path", isPresented: $showingBrewError) {} message: {
                Text(DependencyManager.brokenPathOrIstallMessage)
            }

            // More actions popover
            Button() {
                showingPopover = true
            } label: {
                Image(systemName: "chevron.down")
                    .padding(.vertical)
                    .contentShape(Rectangle())
            }
            .popover(isPresented: $showingPopover) {
                VStack(alignment: .leading, spacing: 6) {
                    // Open homepage
                    if let homepageLink = cask.homepageURL {
                        Link(destination: homepageLink, label: {
                            Label("Homepage", systemImage: "house")
                        })
                        .foregroundColor(.primary)
                    } else {
                        Text("No homepage found")
                            .fontWeight(.thin)
                    }

                    // Force install button
                    Button {
                        showingForceInstallConfirmation = true
                    } label: {
                        Label("Force Install", systemImage: "bolt.trianglebadge.exclamationmark.fill")
                    }
                }
                .padding(8)
                .buttonStyle(.plain)
            }
            .confirmationDialog("Are you sure you want to force install \(cask.name)? This will override any current installation!", isPresented: $showingForceInstallConfirmation) {
                Button("Yes") {
                    download(force: true)
                }

                Button("Cancel", role: .cancel) { }
            }
        }

        private func download(force: Bool = false) {
            // Check if brew path is valid
            guard BrewPaths.isSelectedBrewPathValid() else {
                showingBrewError = true
                return
            }

            Task {
                await cask.install(caskData: caskData, force: force)
            }
        }
    }
}
