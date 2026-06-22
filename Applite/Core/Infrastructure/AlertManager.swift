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
@Observable
final class AlertManager {
    var isPresented: Bool = false
    var title: LocalizedStringKey = ""
    var message: String = ""
    var primaryButtonTitle: String = "OK"
    var primaryAction: (() -> Void)?

    /// Presents alert
    func show(
        title: LocalizedStringKey,
        message: String = "",
        primaryButtonTitle: String = "OK",
        primaryAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message.limitedToLines(20, suffix: "...")
        self.primaryButtonTitle = primaryButtonTitle
        self.primaryAction = primaryAction
        self.isPresented = true
    }

    /// Shows an alert based on an error
    func show(
        error: Error,
        title: LocalizedStringKey,
        primaryButtonTitle: String = "OK",
        primaryAction: (() -> Void)? = nil
    ) {
        show(
            title: title,
            message: error.localizedDescription,
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
