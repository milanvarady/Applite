//
//  ContentView+LoadCasks.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension ContentView {
    func loadCasks() async {
        guard await BrewPaths.isSelectedBrewPathValid() else {
            loadAlert.show(title: "Couldn't load app catalog", message: DependencyManager.brokenPathOrIstallMessage)
            brokenInstall = true

            let output = (try? await Shell.runBrewCommand(["--version"])) ?? "n/a"

            logger.error(
                """
                Initial cask load failure. Reason: selected brew path seems invalid.
                Brew executable path path: \(BrewPaths.currentBrewExecutable.path(percentEncoded: false))
                brew --version output: \(output)
                """
            )

            return
        }

        do {
            try await caskManager.loadData()
            brokenInstall = false

            // Sync currently installed cask IDs to iCloud
            let installedIds = Set(caskManager.installedCasks.casks.map(\.id))
            iCloudSyncManager.addCasks(installedIds)
        } catch {
            loadAlert.show(title: "Couldn't load app catalog", message: error.localizedDescription)
            logger.error("Initial cask load failure. Reason: \(error.localizedDescription)")
        }
    }
}
