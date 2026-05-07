//
//  AlertManagerViewModifier.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.27.
//

import SwiftUI

struct AlertModifier: ViewModifier {
    @Binding var manager: AlertManager

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
    func alertManager(_ manager: Binding<AlertManager>) -> some View {
        modifier(AlertModifier(manager: manager))
    }
}
