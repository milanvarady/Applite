//
//  BrewInfoView.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.01.
//

import SwiftUI

struct BrewInfoView: View {
    // These will be loaded in asynchronously (nil = still loading)
    @State var homebrewVersion: String? = nil
    @State var numberOfCasks: String? = nil

    var body: some View {
        Section("Info") {
            LabeledContent("Homebrew Version") {
                infoValue(homebrewVersion)
            }

            LabeledContent("Apps Installed") {
                infoValue(numberOfCasks)
            }
        }
        .task {
            // Resolved independently so a failure in one doesn't blank out the other.
            homebrewVersion = await loadHomebrewVersion()
            numberOfCasks = await loadInstalledCaskCount()
        }
    }

    private func loadHomebrewVersion() async -> String {
        // The annex is a tarball with no `.git`, so brew can't resolve an exact version and reports
        // e.g. "Homebrew >=4.3.0 (shallow or no git repository)". Capture the whole version token
        // (including a possible `>=`), not just leading digits.
        guard let output = try? await Shell.runBrewCommand(["--version"]),
              let match = output.firstMatch(of: /Homebrew (\S+)/) else {
            return String(localized: "Error", comment: "Brew info value when loading fails")
        }

        return String(match.1)
    }

    private func loadInstalledCaskCount() async -> String {
        // `-1` prints one cask per line; count non-empty lines instead of shelling out to `wc`.
        guard let output = try? await Shell.runBrewCommand(["list", "--cask", "-1"]) else {
            return String(localized: "Error", comment: "Brew info value when loading fails")
        }

        return String(output.split(whereSeparator: \.isNewline).count)
    }

    @ViewBuilder
    private func infoValue(_ value: String?) -> some View {
        if let value {
            Text(value)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }
}
