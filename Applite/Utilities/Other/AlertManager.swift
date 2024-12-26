//
//  AlertManager.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import Foundation
import SwiftUI

/// A helper class for easier alert management
@MainActor
final class AlertManager: ObservableObject {
    @Published var isPresented: Bool = false
    @Published var title: String = ""
    @Published var message: String = ""
    @Published var primaryButtonTitle: String = "OK"
    @Published var primaryAction: (() -> Void)?

    /// Presents alert
    func show(
        title: String,
        message: String = "",
        primaryButtonTitle: String = "OK",
        primaryAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.primaryButtonTitle = primaryButtonTitle
        self.primaryAction = primaryAction
        self.isPresented = true
    }

    /// Shows an alert based on an error
    func show(
        error: LocalizedError,
        overrideTitle: String? = nil,
        primaryButtonTitle: String = "OK",
        primaryAction: (() -> Void)? = nil
    ) {
        let title = overrideTitle ?? error.errorDescription ?? error.localizedDescription

        show(
            title: title,
            message: error.failureReason ?? "",
            primaryButtonTitle: primaryButtonTitle,
            primaryAction: primaryAction
        )
    }

    /// Resets values
    func dismiss() {
        title = ""
        message = ""
        primaryButtonTitle = "OK"
        primaryAction = nil
    }
}

struct AlertModifier: ViewModifier {
    @ObservedObject var manager: AlertManager

    func body(content: Content) -> some View {
        content
            .alert(manager.title, isPresented: $manager.isPresented) {
                Button(manager.primaryButtonTitle) {
                    manager.primaryAction?()
                    manager.dismiss()
                }

                // Add cancel button if we have a primary action
                if manager.primaryAction != nil {
                    Button("Cancel", role: .cancel) {
                        manager.dismiss()
                    }
                }
            } message: {
                Text(manager.message)
            }
    }
}

extension View {
    func alertManager(_ manager: AlertManager) -> some View {
        modifier(AlertModifier(manager: manager))
    }
}
