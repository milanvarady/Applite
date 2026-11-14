//
//  IconAndDescriptionView.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

struct IconAndDescriptionView: View {
    var cask: CaskViewModel
    var isLoadingDetails: Bool
    var showDetails: () -> Void
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        HStack {
            if let iconURL = cask.iconURL {
                AppIconView(
                    iconURL: iconURL,
                    name: cask.name,
                    cacheKey: cask.iconCacheKey
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
                    Text(cask.name)
                        .font(.system(size: 16, weight: .bold))
                        .overlay(alignment: .bottom) {
                            if isLoadingDetails {
                                ProgressView()
                                    .progressViewStyle(.linear)
                                    .controlSize(.mini)
                                    .frame(height: 2)
                                    .offset(y: 3)
                                    .accessibilityHidden(true)
                            }
                        }
                }
                .buttonStyle(.plain)
                .disabled(isLoadingDetails)
                .accessibilityLabel("Show details for \(cask.name)")
                .help(isLoadingDetails ? Text("Loading app details...") : Text("Show app details"))

                Text(cask.descriptionText)
                    .foregroundStyle(.secondary)

                if cask.isInstalled {
                    Text("Installed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if cask.isInstalledExternally {
                    Text("Installed externally")
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
}
