//
//  AppView+GetInfoButton.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.02.
//

import SwiftUI
import ButtonKit
import OSLog

extension AppView {
    struct GetInfoButton: View {
        var cask: CaskViewModel
        @Environment(CaskManager.self) var caskManager
        @Environment(\.openWindow) var openWindow

        @State var alert = AlertManager()

        private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "GetInfoButton")

        var body: some View {
            AsyncButton {
                let caskInfo = try await caskManager.getAdditionalInfoForCask(cask)
                openWindow(value: caskInfo)
            } label: {
                Label("Get Info", systemImage: "info.circle")
            }
            .onButtonStateError { error in
                alert.show(error: error.error, title: "Failed to gather cask info")
                logger.error("Failed to gather additional cask info: \(error.error.localizedDescription)")
            }
            .asyncButtonStyle(.trailing)
            .alertManager($alert)
        }
    }
}
