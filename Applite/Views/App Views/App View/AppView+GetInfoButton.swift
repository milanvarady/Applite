//
//  AppView+GetInfoButton.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.02.
//

import SwiftUI

extension AppView {
    struct GetInfoButton: View {
        @ObservedObject var cask: Cask
        @EnvironmentObject var caskManager: CaskManager
        @Environment(\.openWindow) var openWindow

        @StateObject var alert = AlertManager()

        var body: some View {
            Button {
                Task {
                    do {
                        let caskInfo = try await caskManager.getAdditionalInfoForCask(cask)
                        openWindow(value: caskInfo)
                    } catch {
                        alert.show(error: error, title: "Failed to gather cask info")
                    }
                }
            } label: {
                Label("Get Info", systemImage: "info.circle")
            }
            .alertManager(alert)
        }
    }
}
