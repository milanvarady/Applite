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
    var updateVersion: UpdateVersionState? = nil
    var retryUpdateVersions: () -> Void = {}
    @Environment(\.openURL) private var openURL
    @State private var isHoveringDetails = false
    private var isUpdate: Bool {
        if case .some = updateVersion { return true }
        return false
    }
    
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
                            .lineLimit(isUpdate ? 1 : nil)

                        if !isUpdate {
                            Text(cask.descriptionText)
                                .foregroundStyle(.secondary)
                        }
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

                if let updateVersion {
                    switch updateVersion {
                    case .loading:
                        Text("Loading versions...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .loaded(let versions, let error):
                        let installed = versions.installed ?? String(localized: "Unknown")
                        let available = versions.available ?? String(localized: "Unknown")
                        HStack(spacing: 4) {
                            Text("\(installed) → \(available)")
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(String(localized: "Installed: \(installed); Homebrew available: \(available)"))
                                .accessibilityLabel("Installed: \(installed); Homebrew available: \(available)")
                            if let error {
                                Button(action: retryUpdateVersions) {
                                    Image(systemName: "exclamationmark.triangle")
                                }
                                .accessibilityLabel("Couldn't load versions: \(error). Retry")
                                .help(error)
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
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
