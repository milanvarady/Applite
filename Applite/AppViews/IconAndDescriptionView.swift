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

                        Text(cask.descriptionText)
                            .foregroundStyle(.secondary)
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

                if cask.isLocallyInstalled {
                    Text("Installed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
