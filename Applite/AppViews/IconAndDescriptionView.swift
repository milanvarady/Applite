//
//  IconAndDescriptionView.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

struct IconAndDescriptionView: View {
    var cask: CaskViewModel
    var showDetails: () -> Void
    var showReleaseNotes = false
    @Environment(\.openURL) private var openURL
    @State private var isHoveringDetails = false
    
    var body: some View {
        HStack {
            if let iconURL = cask.iconURL {
                AppIconView(
                    iconURL: iconURL,
                    name: cask.name,
                    cacheKey: cask.iconCacheKey,
                    homepageURL: cask.homepage
                )
                .padding(.leading, 5)
            }

            // Name and description
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    // The outer gesture owns Cmd-click; do not also open details.
                    guard !NSEvent.modifierFlags.contains(.command) else { return }
                    showDetails()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(cask.name)
                            .font(.system(size: 16, weight: .bold))
                            .lineLimit(showReleaseNotes ? 1 : nil)

                        Text(cask.descriptionText)
                            .foregroundStyle(.secondary)
                            .lineLimit(showReleaseNotes ? 1 : nil)
                    }
                    .multilineTextAlignment(.leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover(perform: updateDetailsCursor)
                .onDisappear {
                    updateDetailsCursor(false)
                }
                .accessibilityLabel("Show details for \(cask.name)")
                .accessibilityHint(cask.descriptionText)
                .help("Show app details")

                if showReleaseNotes {
                    Button("Release Notes") {
                        guard !NSEvent.modifierFlags.contains(.command) else { return }
                        showDetails()
                    }
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Release Notes for \(cask.name)")
                        .help("Show release notes and version information")
                } else if cask.isLocallyInstalled {
                    Text("Installed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if cask.hasMultipleInstalledCopies || cask.isAdditionalInstalledCopy,
                       let url = cask.selectedInstallationURL {
                        Text(url.deletingLastPathComponent().path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .help(url.path)
                    }
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture()
                .modifiers(.command)
                .onEnded {
                    if let url = cask.homepage {
                        openURL(url)
                    }
                }
        )
    }

    private func updateDetailsCursor(_ hovering: Bool) {
        guard hovering != isHoveringDetails else { return }
        isHoveringDetails = hovering
        if hovering {
            NSCursor.pointingHand.push()
        } else {
            NSCursor.pop()
        }
    }
}
